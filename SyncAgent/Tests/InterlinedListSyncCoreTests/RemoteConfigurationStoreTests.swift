import XCTest
@testable import InterlinedListSyncCore

/// The read/write half of the move to per-machine app settings (GitHub issue
/// #104): what a read means, when a migration is allowed, and what the agent
/// does when its background write loses the compare-and-set race.
final class RemoteConfigurationStoreTests: XCTestCase {

    private let deviceID = "mac-1"

    private func makeStore(
        api: FakeDeviceSettingsAPI,
        identity: any DeviceIdentifying
    ) -> RemoteConfigurationStore {
        RemoteConfigurationStore(api: api, identity: identity, deviceName: "Studio Mac")
    }

    private func sampleConfiguration(machineID: String? = nil) -> SyncAgentConfiguration {
        SyncAgentConfiguration(
            syncEnabled: true,
            pollIntervalSeconds: 90,
            folder: machineID.map {
                SyncFolderReference(
                    bookmark: Data("bm".utf8),
                    displayPath: "/Users/someone/Vault",
                    machineID: $0
                )
            }
        )
    }

    // MARK: - Happy path

    func test_givenNothingStored_whenSaving_thenItCreatesTheDocumentAtBaseVersionZero() async throws {
        let api = FakeDeviceSettingsAPI()
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        try await store.save(sampleConfiguration(machineID: deviceID))

        let writes = await api.writes
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.baseVersion, 0)
        XCTAssertEqual(writes.first?.deviceId, deviceID)
        let stored = await api.storedSettings()
        XCTAssertEqual(stored[DocumentSyncSettingsKeys.pollIntervalSeconds]?.doubleValue, 90)
    }

    func test_givenAStoredConfiguration_whenLoading_thenItIsReturned() async throws {
        let api = FakeDeviceSettingsAPI()
        await api.seed(
            settings: sampleConfiguration(machineID: deviceID).apply(to: [:]),
            version: 4
        )
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        let state = await store.load()

        guard case .stored(let configuration) = state else {
            return XCTFail("Expected a stored configuration, got \(state)")
        }
        XCTAssertEqual(configuration.pollIntervalSeconds, 90)
        XCTAssertEqual(configuration.folder?.displayPath, "/Users/someone/Vault")
    }

    func test_givenAStoredConfiguration_whenSaving_thenItWritesAgainstTheVersionItRead() async throws {
        let api = FakeDeviceSettingsAPI()
        await api.seed(settings: sampleConfiguration(machineID: deviceID).apply(to: [:]), version: 7)
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        var updated = sampleConfiguration(machineID: deviceID)
        updated.pollIntervalSeconds = 300
        try await store.save(updated)

        let writes = await api.writes
        // No explicit load() first: the store reads before its first write so the
        // overlay has the real document to preserve and a version to send.
        XCTAssertEqual(writes.map(\.baseVersion), [7])
        let version = await api.storedVersion()
        XCTAssertEqual(version, 8)
    }

    // MARK: - Invalid input

    func test_givenNoPublishedDeviceID_whenLoading_thenItIsUnavailableAndNothingIsRequested() async {
        let api = FakeDeviceSettingsAPI()
        let store = makeStore(api: api, identity: StaticDeviceIdentity(nil))

        let state = await store.load()

        XCTAssertEqual(state, .unavailable)
        let reads = await api.reads
        XCTAssertTrue(reads.isEmpty, "Nothing is addressable without a device id")
    }

    func test_givenNoPublishedDeviceID_whenSaving_thenItThrowsWithoutCallingTheAPI() async {
        let api = FakeDeviceSettingsAPI()
        let store = makeStore(api: api, identity: StaticDeviceIdentity(nil))

        do {
            try await store.save(sampleConfiguration())
            XCTFail("Expected a failure")
        } catch {
            XCTAssertEqual(error as? APIError, .noDeviceIdentity)
        }
        let writes = await api.writes
        XCTAssertTrue(writes.isEmpty)
    }

    // MARK: - Upstream failure

    func test_givenTheReadFails_whenLoading_thenItIsUnavailableRatherThanAbsent() async {
        let api = FakeDeviceSettingsAPI()
        await api.failReads(with: .transport("offline"))
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        let state = await store.load()

        // The distinction is the whole safety property: `.absent` would invite a
        // migration that overwrites a server document this client never saw.
        XCTAssertEqual(state, .unavailable)
    }

    func test_givenTheWriteKeepsConflicting_whenSaving_thenItGivesUpRatherThanRetryingForever() async {
        let api = FakeDeviceSettingsAPI()
        await api.seed(settings: [:], version: 1)
        await api.failNextWrites(with: [
            .versionConflict(current: nil),
            .versionConflict(current: nil),
            .versionConflict(current: nil)
        ])
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        do {
            try await store.save(sampleConfiguration(machineID: deviceID))
            XCTFail("Expected a failure")
        } catch {
            guard case APIError.versionConflict = error else {
                return XCTFail("Expected a version conflict, got \(error)")
            }
        }
        let writes = await api.writes
        XCTAssertEqual(writes.count, 3, "Retries are bounded, not unlimited")
    }

    // MARK: - Compare-and-set

    func test_givenTheDocumentMovedOn_whenSaving_thenItRebasesFromThe409AndSucceeds() async throws {
        let api = FakeDeviceSettingsAPI()
        let winner = DeviceSettingsDocument(
            version: 9,
            deviceId: deviceID,
            settings: ["theme": .string("dark")]
        )
        await api.seed(settings: ["theme": .string("dark")], version: 9)
        // The store's first write is built on a stale version, exactly as a
        // background write racing the Applications pane would be.
        await api.failNextWrites(with: [.versionConflict(current: winner)])
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        try await store.save(sampleConfiguration(machineID: deviceID))

        let writes = await api.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.last?.baseVersion, 9, "Re-based onto the winning document")
        // Re-basing must also adopt the winner's payload, or the retry would
        // delete keys the other writer had just added.
        XCTAssertEqual(writes.last?.settings["theme"]?.stringValue, "dark")
        let reads = await api.reads
        XCTAssertEqual(reads.count, 1, "The 409 body carried the winner; no extra read")
    }

    func test_givenA409WithNoBody_whenSaving_thenItRereadsAndRetries() async throws {
        let api = FakeDeviceSettingsAPI()
        await api.seed(settings: ["theme": .string("dark")], version: 3)
        await api.failNextWrites(with: [.versionConflict(current: nil)])
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        try await store.save(sampleConfiguration(machineID: deviceID))

        let reads = await api.reads
        XCTAssertEqual(reads.count, 2, "One read before the first write, one to re-base")
        let writes = await api.writes
        XCTAssertEqual(writes.last?.baseVersion, 3)
    }

    func test_givenThisMacIsNotInTheRegistry_whenSaving_thenItRegistersOnceAndRetries() async throws {
        let api = FakeDeviceSettingsAPI()
        await api.failNextWrites(with: [.deviceNotRegistered])
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        try await store.save(sampleConfiguration(machineID: deviceID))

        let registrations = await api.registrations
        XCTAssertEqual(registrations, [deviceID])
        let writes = await api.writes
        XCTAssertEqual(writes.count, 2)
    }

    func test_givenRegistrationDoesNotHelp_whenSaving_thenItStopsInsteadOfLooping() async {
        let api = FakeDeviceSettingsAPI()
        await api.failNextWrites(with: [.deviceNotRegistered, .deviceNotRegistered])
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        do {
            try await store.save(sampleConfiguration(machineID: deviceID))
            XCTFail("Expected a failure")
        } catch {
            XCTAssertEqual(error as? APIError, .deviceNotRegistered)
        }
        let registrations = await api.registrations
        XCTAssertEqual(registrations.count, 1, "Registering twice would not change the answer")
    }

    // MARK: - Boundary

    func test_givenNothingStored_whenLoading_thenItIsAbsent() async {
        let api = FakeDeviceSettingsAPI()
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        let state = await store.load()

        XCTAssertEqual(state, .absent)
    }

    func test_givenOnlyTheMainAppsKeys_whenLoadingThenSaving_thenThoseKeysSurvive() async throws {
        let api = FakeDeviceSettingsAPI()
        await api.seed(settings: ["sidebarWidth": .number(280)], version: 2)
        let store = makeStore(api: api, identity: StaticDeviceIdentity(deviceID))

        // A document with no agent keys reads as absent — the agent has never
        // run here — but its contents must still survive the migration write.
        let state = await store.load()
        XCTAssertEqual(state, .absent)
        try await store.save(sampleConfiguration(machineID: deviceID))

        let stored = await api.storedSettings()
        XCTAssertEqual(stored["sidebarWidth"]?.doubleValue, 280)
        XCTAssertNotNil(stored[DocumentSyncSettingsKeys.enabled])
    }
}

// MARK: - The launch decision

/// ``ConfigurationResolver`` is four cases of pure logic guarding the one thing
/// in this feature that can destroy a user's settings, so it gets its own tests
/// with no network, Keychain, or clock in the way.
final class ConfigurationResolverTests: XCTestCase {

    private let local = SyncAgentConfiguration(syncEnabled: false, pollIntervalSeconds: 45)
    private let remote = SyncAgentConfiguration(syncEnabled: true, pollIntervalSeconds: 300)

    func test_givenBothSourcesHoldAValue_whenResolving_thenTheStoredOneWinsAndNothingMigrates() {
        let resolution = ConfigurationResolver.resolve(
            remote: .stored(remote),
            local: local,
            hasMigrated: false
        )

        XCTAssertEqual(resolution.configuration, remote)
        XCTAssertFalse(resolution.shouldMigrate)
    }

    func test_givenAFreshInstallWithNothingStoredEitherSide_whenResolving_thenDefaultsMigrateUp() {
        let defaults = SyncAgentConfiguration()

        let resolution = ConfigurationResolver.resolve(
            remote: .absent,
            local: defaults,
            hasMigrated: false
        )

        XCTAssertEqual(resolution.configuration, defaults)
        XCTAssertTrue(resolution.shouldMigrate)
    }

    func test_givenLocalSettingsAndAnEmptyServer_whenResolving_thenTheyMigrateUpOnce() {
        let resolution = ConfigurationResolver.resolve(
            remote: .absent,
            local: local,
            hasMigrated: false
        )

        XCTAssertEqual(resolution.configuration, local)
        XCTAssertTrue(resolution.shouldMigrate)
    }

    func test_givenAlreadyMigratedAndTheDocumentIsGone_whenResolving_thenItIsNotRecreated() {
        // The machine was deregistered, or the settings were deleted on purpose.
        // Re-uploading them would resurrect what the user removed.
        let resolution = ConfigurationResolver.resolve(
            remote: .absent,
            local: local,
            hasMigrated: true
        )

        XCTAssertEqual(resolution.configuration, local)
        XCTAssertFalse(resolution.shouldMigrate)
    }

    func test_givenTheServerCannotBeReached_whenResolving_thenNothingMigrates() {
        // The dangerous case: treating "could not ask" as "nothing stored" would
        // overwrite a newer server document with a stale local one.
        let resolution = ConfigurationResolver.resolve(
            remote: .unavailable,
            local: local,
            hasMigrated: false
        )

        XCTAssertEqual(resolution.configuration, local)
        XCTAssertFalse(resolution.shouldMigrate)
    }
}
