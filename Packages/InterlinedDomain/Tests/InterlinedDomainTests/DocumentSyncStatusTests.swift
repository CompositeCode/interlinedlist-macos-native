import XCTest
@testable import InterlinedDomain

/// Reading the Document Sync Agent's state out of a machine's per-machine
/// settings document (GitHub issue #104), so Settings ▸ Applications can say
/// what a machine is doing rather than only that it exists.
///
/// The keys are a wire contract with `DocumentSyncSettingsKeys` in the agent
/// package, which shares no code with this one — so these tests spell the key
/// strings out literally. A test that reused a constant from the same file it is
/// testing would pass just as happily after a rename that broke the contract.
final class DocumentSyncStatusTests: XCTestCase {

    private let deviceID = "mac-1"

    private func bag(
        enabled: Bool = true,
        bookmark: String? = "YmFzZTY0",
        machineID: String? = "mac-1",
        lastSyncAt: String? = "2026-09-16T19:39:07.135Z"
    ) -> AppSettingsBag {
        var bag = AppSettingsBag()
        bag[bool: "documentSync.enabled"] = enabled
        bag[string: "documentSync.folderBookmark"] = bookmark
        bag[string: "documentSync.folderMachineId"] = machineID
        bag[string: "documentSync.lastSyncAt"] = lastSyncAt
        return bag
    }

    // MARK: - Happy path

    func test_givenAMachineRunningTheAgent_whenReadingItsDocument_thenItReportsConfiguredAndOn() throws {
        let status = try XCTUnwrap(DocumentSyncStatus(bag: bag(), deviceID: deviceID))

        XCTAssertTrue(status.isConfigured)
        XCTAssertTrue(status.isEnabled)
        let lastSync = try XCTUnwrap(status.lastSyncAt)
        XCTAssertEqual(lastSync.timeIntervalSince1970, 1_789_587_547.135, accuracy: 0.01)
    }

    func test_givenAConfiguredButPausedMachine_whenReadingItsDocument_thenItIsConfiguredAndOff() throws {
        let status = try XCTUnwrap(
            DocumentSyncStatus(bag: bag(enabled: false), deviceID: deviceID)
        )

        // Configured and paused is a real, distinct state — the folder is set up,
        // the user just switched syncing off.
        XCTAssertTrue(status.isConfigured)
        XCTAssertFalse(status.isEnabled)
    }

    // MARK: - Invalid input

    func test_givenAFolderChosenOnAnotherMac_whenReadingTheDocument_thenItIsNotConfiguredHere() throws {
        let status = try XCTUnwrap(
            DocumentSyncStatus(bag: bag(machineID: "mac-2"), deviceID: deviceID)
        )

        // A security-scoped bookmark is meaningless anywhere but where it was
        // made, so reporting it as configured would promise something untrue.
        XCTAssertFalse(status.isConfigured)
    }

    func test_givenABookmarkWithNoMachineStamp_whenReadingTheDocument_thenItIsNotConfiguredHere() throws {
        let status = try XCTUnwrap(
            DocumentSyncStatus(bag: bag(machineID: nil), deviceID: deviceID)
        )

        XCTAssertFalse(status.isConfigured)
    }

    // MARK: - Upstream failure (a payload this build does not understand)

    func test_givenAnUnparseableTimestamp_whenReadingTheDocument_thenTheRestStillReports() throws {
        let status = try XCTUnwrap(
            DocumentSyncStatus(bag: bag(lastSyncAt: "yesterday"), deviceID: deviceID)
        )

        // The payload is client-owned and opaque to the server, so a future build
        // may store something this one cannot read. One unreadable field must not
        // take the whole pane down with it.
        XCTAssertNil(status.lastSyncAt)
        XCTAssertTrue(status.isConfigured)
    }

    func test_givenAFieldOfTheWrongType_whenReadingTheDocument_thenItDegradesToUnset() throws {
        var mixed = bag()
        // A build that stored the flag as a string rather than a bool.
        mixed[string: "documentSync.enabled"] = "yes"

        let status = try XCTUnwrap(DocumentSyncStatus(bag: mixed, deviceID: deviceID))

        XCTAssertFalse(status.isEnabled)
        XCTAssertTrue(status.isConfigured)
    }

    // MARK: - Boundary

    func test_givenAMachineThatHasNeverRunTheAgent_whenReadingItsDocument_thenThereIsNothingToReport() {
        var other = AppSettingsBag()
        other[int: "sidebarWidth"] = 280

        // Distinct from "installed but switched off" — the pane shows no Document
        // Sync section at all rather than asserting the agent is off.
        XCTAssertNil(DocumentSyncStatus(bag: other, deviceID: deviceID))
    }

    func test_givenAnEmptyDocument_whenReadingIt_thenThereIsNothingToReport() {
        XCTAssertNil(DocumentSyncStatus(bag: AppSettingsBag(), deviceID: deviceID))
    }

    func test_givenTheAgentRanButNoFolderWasChosen_whenReadingTheDocument_thenItIsNotConfigured() throws {
        let status = try XCTUnwrap(
            DocumentSyncStatus(bag: bag(bookmark: nil), deviceID: deviceID)
        )

        XCTAssertFalse(status.isConfigured)
        XCTAssertTrue(status.isEnabled)
    }

    func test_givenAnEmptyBookmarkString_whenReadingTheDocument_thenItIsNotConfigured() throws {
        let status = try XCTUnwrap(
            DocumentSyncStatus(bag: bag(bookmark: ""), deviceID: deviceID)
        )

        XCTAssertFalse(status.isConfigured)
    }
}
