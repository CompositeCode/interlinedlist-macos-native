// DeviceIdentityTests
//
// This machine's app-settings device id, and the shared-Keychain channel that
// lets the bundled document-sync agent address the *same* per-machine settings
// document the app does (GitHub issue #104).
//
// Two ids for one Mac would mean two rows in the device registry and a
// configuration split across two documents, so the resolution order is the
// behaviour under test — not an implementation detail.

import XCTest
import InterlinedKit
@testable import InterlinedList

final class DeviceIdentityTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "iltest-device-\(UUID().uuidString)")!
    }

    // MARK: - Happy path

    func test_givenAMachineAlreadyRegistered_whenResolving_thenItKeepsTheIdItsRegistryRowUses() {
        let defaults = freshDefaults()
        defaults.set("existing-id", forKey: "com.interlinedlist.deviceId")
        let shared = InMemoryDeviceIDStore()

        let resolved = DeviceIdentity.current(defaults: defaults, sharedStore: shared)

        // Preferring anything else would orphan the registry row and the
        // per-machine settings filed under it.
        XCTAssertEqual(resolved, "existing-id")
        XCTAssertEqual(shared.read(), "existing-id", "…and the agent is told about it")
    }

    func test_givenANewMachine_whenResolving_thenItMintsOnceAndPublishesIt() {
        let defaults = freshDefaults()
        let shared = InMemoryDeviceIDStore()

        let first = DeviceIdentity.current(defaults: defaults, sharedStore: shared)
        let second = DeviceIdentity.current(defaults: defaults, sharedStore: shared)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second, "Minting twice would register the Mac twice")
        XCTAssertEqual(shared.read(), first)
    }

    // MARK: - Boundary: the app's preferences were wiped

    func test_givenTheAppsPreferencesWereWipedButTheAgentRemains_whenResolving_thenThePublishedIdIsAdopted() {
        let defaults = freshDefaults()
        let shared = InMemoryDeviceIDStore(initial: "published-id")

        let resolved = DeviceIdentity.current(defaults: defaults, sharedStore: shared)

        // Reinstalling the app must reunite it with this machine's existing
        // registry row rather than minting a duplicate alongside it.
        XCTAssertEqual(resolved, "published-id")
        XCTAssertEqual(defaults.string(forKey: "com.interlinedlist.deviceId"), "published-id")
    }

    // MARK: - Invalid input

    func test_givenAnEmptyStoredId_whenResolving_thenItIsTreatedAsAbsent() {
        let defaults = freshDefaults()
        defaults.set("", forKey: "com.interlinedlist.deviceId")
        let shared = InMemoryDeviceIDStore()

        let resolved = DeviceIdentity.current(defaults: defaults, sharedStore: shared)

        XCTAssertFalse(resolved.isEmpty)
    }

    func test_givenAnEmptyPublishedId_whenResolving_thenItIsTreatedAsAbsent() {
        let defaults = freshDefaults()
        let shared = InMemoryDeviceIDStore(initial: "")

        let resolved = DeviceIdentity.current(defaults: defaults, sharedStore: shared)

        XCTAssertFalse(resolved.isEmpty)
        XCTAssertEqual(shared.read(), resolved)
    }

    // MARK: - Upstream failure: the Keychain is unavailable

    func test_givenTheSharedStoreCannotBeWritten_whenResolving_thenTheAppStillGetsAnId() {
        // An unsigned build, or one without the shared access-group entitlement,
        // cannot use the Keychain at all. The app degrades to local-only — the
        // agent falls back to its own settings — rather than failing at launch.
        let defaults = freshDefaults()
        let shared = UnwritableDeviceIDStore()

        let resolved = DeviceIdentity.current(defaults: defaults, sharedStore: shared)

        XCTAssertFalse(resolved.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "com.interlinedlist.deviceId"), resolved)
    }
}

/// A shared store that silently drops every write, standing in for a process
/// that is not entitled to the shared Keychain group.
private final class UnwritableDeviceIDStore: DeviceIDStoring, @unchecked Sendable {
    func read() -> String? { nil }
    func write(_ id: String) {}
}
