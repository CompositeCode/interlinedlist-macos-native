import XCTest
@testable import InterlinedListSyncCore

@MainActor
final class PreferencesManagerTests: XCTestCase {

    private let deviceID = "mac-1"

    private func freshDefaults() -> UserDefaults {
        let suite = "iltest-prefs-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    /// Debounced saves are parked far enough out that no test observes one. The
    /// writes these tests assert on are the explicit ones `synchronize()` makes;
    /// a stray coalesced write would make the counts meaningless.
    private func makeManager(
        defaults: UserDefaults,
        api: FakeDeviceSettingsAPI,
        identity: any DeviceIdentifying
    ) -> PreferencesManager {
        PreferencesManager(
            defaults: defaults,
            remote: RemoteConfigurationStore(api: api, identity: identity, deviceName: "Studio Mac"),
            remoteSaveDebounce: .seconds(3600)
        )
    }

    // MARK: - Local behaviour (unchanged by the move to app settings)

    func test_defaults_areSensible() {
        let prefs = PreferencesManager(defaults: freshDefaults())
        XCTAssertEqual(prefs.pollIntervalSeconds, SyncConfiguration.defaultPollInterval)
        XCTAssertTrue(prefs.syncEnabled)
        XCTAssertFalse(prefs.hasSyncFolder)
        XCTAssertNil(prefs.syncFolderPath)
    }

    func test_pollInterval_persistsAndClampsOnReload() {
        let defaults = freshDefaults()
        let prefs = PreferencesManager(defaults: defaults)
        prefs.pollIntervalSeconds = 120
        // Simulate a stored out-of-range value from a previous version.
        defaults.set(5, forKey: "pollIntervalSeconds")
        let reloaded = PreferencesManager(defaults: defaults)
        XCTAssertEqual(reloaded.pollIntervalSeconds, SyncConfiguration.minPollInterval)
    }

    func test_togglesPersist() {
        let defaults = freshDefaults()
        let prefs = PreferencesManager(defaults: defaults)
        prefs.notifyOnCompletion = true
        prefs.launchAtLogin = true
        let reloaded = PreferencesManager(defaults: defaults)
        XCTAssertTrue(reloaded.notifyOnCompletion)
        XCTAssertTrue(reloaded.launchAtLogin)
    }

    // MARK: - Happy path: adopting stored per-machine settings

    func test_givenStoredSettingsForThisMac_whenSynchronizing_thenTheyReplaceTheLocalOnes() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        let stored = SyncAgentConfiguration(
            syncEnabled: false,
            pollIntervalSeconds: 300,
            notifyOnCompletion: true,
            folder: SyncFolderReference(
                bookmark: Data("bm".utf8),
                displayPath: "/Users/someone/Vault",
                machineID: deviceID
            )
        )
        await api.seed(settings: stored.apply(to: [:]), version: 2)
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))

        await prefs.synchronize()

        XCTAssertEqual(prefs.pollIntervalSeconds, 300)
        XCTAssertFalse(prefs.syncEnabled)
        XCTAssertTrue(prefs.notifyOnCompletion)
        // The bookmark reaches local storage, which is the only place the agent
        // ever resolves it from — so a reinstall recovers the folder.
        XCTAssertTrue(prefs.hasSyncFolder)
        XCTAssertEqual(prefs.syncFolderPath, "/Users/someone/Vault")
    }

    // MARK: - Migration

    func test_givenLocalSettingsAndAnEmptyServer_whenSynchronizing_thenTheyMigrateUpAndAreMarkedDone() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))
        prefs.pollIntervalSeconds = 180
        prefs.notifyOnErrors = false

        await prefs.synchronize()

        let stored = await api.storedSettings()
        XCTAssertEqual(stored[DocumentSyncSettingsKeys.pollIntervalSeconds]?.doubleValue, 180)
        XCTAssertEqual(stored[DocumentSyncSettingsKeys.notifyOnErrors]?.boolValue, false)
        XCTAssertTrue(prefs.hasMigratedToAppSettings)
    }

    func test_givenAFreshInstallWithNoLocalSettings_whenSynchronizing_thenTheDefaultsAreStoredOnce() async {
        // The boundary GitHub issue #104 calls out: `UserDefaults` is empty, so
        // there is nothing to migrate but the defaults themselves — and the
        // migration must still be recorded, or it would run again every launch.
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))

        await prefs.synchronize()

        let writes = await api.writes
        XCTAssertEqual(writes.count, 1)
        let stored = await api.storedSettings()
        XCTAssertEqual(
            stored[DocumentSyncSettingsKeys.pollIntervalSeconds]?.doubleValue,
            SyncConfiguration.defaultPollInterval
        )
        XCTAssertTrue(prefs.hasMigratedToAppSettings)
    }

    func test_givenTheMigrationAlreadyRan_whenSynchronizingAgain_thenNothingIsWrittenBack() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))
        await prefs.synchronize()
        let writesAfterMigration = await api.writes.count

        // A second launch with the document now stored. It must read, adopt, and
        // stop — a migration that re-ran every launch would be worse than none.
        await prefs.synchronize()

        let writesAfterSecondLaunch = await api.writes.count
        XCTAssertEqual(writesAfterSecondLaunch, writesAfterMigration)
    }

    // MARK: - Upstream failure

    func test_givenTheServerCannotBeReached_whenSynchronizing_thenLocalSettingsStandAndNothingIsMigrated() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        await api.failReads(with: .transport("offline"))
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))
        prefs.pollIntervalSeconds = 240

        await prefs.synchronize()

        XCTAssertEqual(prefs.pollIntervalSeconds, 240)
        let writes = await api.writes
        XCTAssertTrue(writes.isEmpty, "A failed read must never be read as an empty server")
        XCTAssertFalse(prefs.hasMigratedToAppSettings)
    }

    func test_givenTheMigrationWriteFails_whenSynchronizing_thenItIsNotMarkedDone() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        await api.failNextWrites(with: [.transport("offline"), .transport("offline"), .transport("offline")])
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))

        await prefs.synchronize()

        // Unconfirmed means unmigrated: `UserDefaults` stays the fallback and
        // the next launch tries again.
        XCTAssertFalse(prefs.hasMigratedToAppSettings)
    }

    // MARK: - Boundary: a folder that belongs to another Mac

    func test_givenTheStoredFolderBelongsToAnotherMac_whenSynchronizing_thenThisMacIsNotConfigured() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        let fromAnotherMac = SyncAgentConfiguration(
            pollIntervalSeconds: 300,
            folder: SyncFolderReference(
                bookmark: Data("bm".utf8),
                displayPath: "/Volumes/OtherMac/Vault",
                machineID: "mac-2"
            )
        )
        await api.seed(settings: fromAnotherMac.apply(to: [:]), version: 1)
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))

        await prefs.synchronize()

        // The rest of the configuration still applies; only the folder is
        // refused, and the agent will prompt for one.
        XCTAssertEqual(prefs.pollIntervalSeconds, 300)
        XCTAssertFalse(prefs.hasSyncFolder)
        XCTAssertNil(prefs.syncFolderPath)
    }

    func test_givenTheServerHasNoFolderButThisMacDoes_whenSynchronizing_thenTheLocalFolderSurvives() async {
        // A folder chosen while offline. The stored configuration predates it,
        // and there is no UI for unsetting a folder — so "no folder stored" is
        // never evidence the user cleared one.
        let defaults = freshDefaults()
        defaults.set(Data("local-bm".utf8), forKey: "syncFolderBookmark")
        defaults.set("/Users/someone/Local", forKey: "syncFolderPath")
        let api = FakeDeviceSettingsAPI()
        await api.seed(
            settings: SyncAgentConfiguration(pollIntervalSeconds: 120).apply(to: [:]),
            version: 1
        )
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))

        await prefs.synchronize()

        XCTAssertTrue(prefs.hasSyncFolder)
        XCTAssertEqual(prefs.syncFolderPath, "/Users/someone/Local")
        // …and the server is brought up to date rather than left disagreeing.
        let stored = await api.storedSettings()
        XCTAssertEqual(stored[DocumentSyncSettingsKeys.folderMachineID]?.stringValue, deviceID)
    }

    // MARK: - Boundary: no device id published yet

    func test_givenTheMainAppHasNotPublishedADeviceID_whenSynchronizing_thenNothingIsReadOrWritten() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(nil))

        await prefs.synchronize()

        let reads = await api.reads
        let writes = await api.writes
        XCTAssertTrue(reads.isEmpty)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertFalse(prefs.hasMigratedToAppSettings)
    }

    // MARK: - Reported status

    func test_givenARecentlyPublishedSync_whenAnotherCycleCompletes_thenItIsNotPublishedAgain() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))
        await prefs.synchronize()
        let writesAfterMigration = await api.writes.count

        let now = Date()
        // Awaited rather than slept on: the publish is a task the manager hands
        // back precisely so this assertion needs no timer.
        await prefs.recordSync(at: now)?.value
        let inWindow = prefs.recordSync(at: now.addingTimeInterval(60))
        let alsoInWindow = prefs.recordSync(at: now.addingTimeInterval(120))

        // The first crosses the throttle (nothing published yet); the rest fall
        // inside the window. A settings PUT per poll cycle is what this prevents.
        XCTAssertNil(inWindow)
        XCTAssertNil(alsoInWindow)
        let writesAfterReports = await api.writes.count
        XCTAssertEqual(writesAfterReports, writesAfterMigration + 1)
    }

    func test_givenTheThrottleWindowHasPassed_whenACycleCompletes_thenItIsPublishedAgain() async {
        let defaults = freshDefaults()
        let api = FakeDeviceSettingsAPI()
        let prefs = makeManager(defaults: defaults, api: api, identity: StaticDeviceIdentity(deviceID))
        await prefs.synchronize()
        let writesAfterMigration = await api.writes.count

        let now = Date()
        await prefs.recordSync(at: now)?.value
        await prefs.recordSync(
            at: now.addingTimeInterval(SyncConfiguration.lastSyncPublishInterval + 1)
        )?.value

        let writesAfterReports = await api.writes.count
        XCTAssertEqual(writesAfterReports, writesAfterMigration + 2)
        let stored = await api.storedSettings()
        XCTAssertNotNil(stored[DocumentSyncSettingsKeys.lastSyncAt]?.stringValue)
    }
}
