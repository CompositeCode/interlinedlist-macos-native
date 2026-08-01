import XCTest
@testable import InterlinedListSyncCore

final class ConflictResolverTests: XCTestCase {

    private func decide(_ l: Bool, _ r: Bool, _ le: Bool = true, _ re: Bool = true) -> SyncDecision {
        ConflictResolver.decide(localChanged: l, remoteChanged: r, localExists: le, remoteExists: re)
    }

    func test_bothChanged_isConflict() {
        XCTAssertEqual(decide(true, true), .conflictCopy)
    }

    func test_onlyLocalChanged_isPush() {
        XCTAssertEqual(decide(true, false), .push)
    }

    func test_onlyRemoteChanged_isPull() {
        XCTAssertEqual(decide(false, true), .pull)
    }

    func test_neitherChanged_isNoOp() {
        XCTAssertEqual(decide(false, false), .noOp)
    }

    func test_remoteGone_localUnchanged_deletesLocal() {
        XCTAssertEqual(decide(false, false, true, false), .deleteLocal)
    }

    func test_remoteGone_localChanged_pushesToPreserveWork() {
        XCTAssertEqual(decide(true, false, true, false), .push)
    }

    func test_localGone_remoteUnchanged_deletesRemote() {
        XCTAssertEqual(decide(false, false, false, true), .deleteRemote)
    }

    func test_localGone_remoteChanged_recreatesLocally() {
        XCTAssertEqual(decide(false, true, false, true), .pull)
    }

    func test_neitherExists_isNoOp() {
        XCTAssertEqual(decide(false, false, false, false), .noOp)
    }
}
