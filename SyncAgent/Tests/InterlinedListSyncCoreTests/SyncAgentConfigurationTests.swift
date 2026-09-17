import XCTest
@testable import InterlinedListSyncCore

/// The payload shape the agent stores in per-machine app settings (GitHub issue
/// #104) — in particular the rule that a security-scoped bookmark belonging to
/// another Mac is not a configuration, it is noise.
final class SyncAgentConfigurationTests: XCTestCase {

    private let thisMachine = "mac-1"
    private let bookmark = Data("bookmark-bytes".utf8)

    private func configured(machineID: String) -> SyncAgentConfiguration {
        SyncAgentConfiguration(
            syncEnabled: false,
            pollIntervalSeconds: 120,
            launchAtLogin: true,
            notificationsEnabled: false,
            notifyOnCompletion: true,
            notifyOnErrors: false,
            notifyOnConflicts: false,
            folder: SyncFolderReference(
                bookmark: bookmark,
                displayPath: "/Users/someone/Vault",
                machineID: machineID
            ),
            lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Happy path

    func test_givenAConfigurationWithAFolder_whenWrittenAndReadBack_thenEveryFieldSurvives() throws {
        let original = configured(machineID: thisMachine)

        let payload = original.apply(to: [:])
        let restored = try XCTUnwrap(
            SyncAgentConfiguration(settings: payload, thisMachineID: thisMachine)
        )

        XCTAssertEqual(restored, original)
        XCTAssertEqual(
            payload[DocumentSyncSettingsKeys.schemaVersion]?.doubleValue,
            Double(SyncConfiguration.settingsSchemaVersion)
        )
    }

    func test_givenADocumentWrittenHere_whenRead_thenTheFolderIsAccepted() throws {
        let payload = configured(machineID: thisMachine).apply(to: [:])

        let restored = try XCTUnwrap(
            SyncAgentConfiguration(settings: payload, thisMachineID: thisMachine)
        )

        XCTAssertEqual(restored.folder?.bookmark, bookmark)
        XCTAssertEqual(restored.folder?.displayPath, "/Users/someone/Vault")
    }

    // MARK: - Invalid input

    func test_givenABookmarkFromAnotherMac_whenRead_thenTheMachineIsNotConfiguredHere() throws {
        let payload = configured(machineID: "mac-2").apply(to: [:])

        let restored = try XCTUnwrap(
            SyncAgentConfiguration(settings: payload, thisMachineID: thisMachine)
        )

        // Everything else still applies — only the folder is refused, because
        // only the folder is machine-local.
        XCTAssertNil(restored.folder)
        XCTAssertEqual(restored.pollIntervalSeconds, 120)
        XCTAssertFalse(restored.syncEnabled)
    }

    func test_givenABookmarkWithNoMachineStamp_whenRead_thenTheFolderIsRefused() throws {
        var payload = configured(machineID: thisMachine).apply(to: [:])
        payload[DocumentSyncSettingsKeys.folderMachineID] = nil

        let restored = try XCTUnwrap(
            SyncAgentConfiguration(settings: payload, thisMachineID: thisMachine)
        )

        XCTAssertNil(restored.folder)
    }

    func test_givenAPollIntervalBelowTheFloor_whenRead_thenItIsClamped() throws {
        var payload = configured(machineID: thisMachine).apply(to: [:])
        payload[DocumentSyncSettingsKeys.pollIntervalSeconds] = .number(1)

        let restored = try XCTUnwrap(
            SyncAgentConfiguration(settings: payload, thisMachineID: thisMachine)
        )

        XCTAssertEqual(restored.pollIntervalSeconds, SyncConfiguration.minPollInterval)
    }

    // MARK: - Boundary

    func test_givenADocumentWithNoAgentKeys_whenRead_thenThereIsNoStoredConfiguration() {
        // The main app may well have stored per-machine settings of its own.
        // That is not a configuration this agent wrote, so the migration must
        // still be allowed to run.
        let payload: [String: SettingsValue] = ["sidebarWidth": .number(280)]

        XCTAssertNil(SyncAgentConfiguration(settings: payload, thisMachineID: thisMachine))
    }

    func test_givenAnEmptyDocument_whenRead_thenThereIsNoStoredConfiguration() {
        XCTAssertNil(SyncAgentConfiguration(settings: [:], thisMachineID: thisMachine))
    }

    // MARK: - Shared document

    func test_givenKeysOwnedByAnotherClient_whenWriting_thenTheySurvive() {
        let existing: [String: SettingsValue] = [
            "sidebarWidth": .number(280),
            "theme": .string("dark")
        ]

        let payload = configured(machineID: thisMachine).apply(to: existing)

        // The PUT replaces the document wholesale, so anything the overlay drops
        // is deleted from the server. These keys belong to the main app.
        XCTAssertEqual(payload["sidebarWidth"]?.doubleValue, 280)
        XCTAssertEqual(payload["theme"]?.stringValue, "dark")
    }

    func test_givenAStoredFolder_whenWritingAConfigurationWithoutOne_thenTheStaleFolderKeysGo() {
        let existing = configured(machineID: thisMachine).apply(to: [:])
        var unconfigured = configured(machineID: thisMachine)
        unconfigured.folder = nil

        let payload = unconfigured.apply(to: existing)

        // Rebuilt from scratch inside the namespace: leaving a stale bookmark
        // behind would let a cleared folder come back on the next read.
        XCTAssertNil(payload[DocumentSyncSettingsKeys.folderBookmark])
        XCTAssertNil(payload[DocumentSyncSettingsKeys.folderPath])
        XCTAssertNil(payload[DocumentSyncSettingsKeys.folderMachineID])
    }
}
