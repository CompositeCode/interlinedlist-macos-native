import XCTest
@testable import InterlinedListSyncCore

final class ChangeSetTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_100)

    private func remote(_ id: String, content: String, updatedAt: Date, folderId: String? = nil, deleted: Bool = false) -> RemoteDocState {
        RemoteDocState(id: id, title: id, content: content, folderId: folderId, updatedAt: updatedAt, isDeleted: deleted)
    }

    private func local(_ id: String, body: String, path: String = "") -> LocalDocState {
        LocalDocState(
            id: id, url: URL(fileURLWithPath: "/tmp/\(id).md"), title: id,
            contentHash: ContentHash.sha256(body), folderRelativePath: path, modifiedAt: t0
        )
    }

    private func entry(_ body: String, updatedAt: Date) -> LedgerEntry {
        LedgerEntry(remoteUpdatedAt: updatedAt, contentHash: ContentHash.sha256(body), folderId: nil, relativeFilePath: "")
    }

    func test_newRemoteDoc_isPulled() {
        let plan = ChangeSet.compute(
            remote: ["a": remote("a", content: "hi", updatedAt: t0)],
            remoteIsComplete: false, tracked: [:], untracked: [], ledger: [:]
        )
        XCTAssertEqual(plan.pull, ["a"])
    }

    func test_untrackedFile_isCreated() {
        let file = ScannedDocument(
            url: URL(fileURLWithPath: "/tmp/new.md"), documentID: nil, title: "new",
            body: "x", modifiedAt: t0, contentHash: ContentHash.sha256("x"), folderRelativePath: ""
        )
        let plan = ChangeSet.compute(remote: [:], remoteIsComplete: false, tracked: [:], untracked: [file], ledger: [:])
        XCTAssertEqual(plan.create, [file.url])
    }

    func test_localEdit_isPushed_whenRemoteUnchanged() {
        let plan = ChangeSet.compute(
            remote: ["a": remote("a", content: "old", updatedAt: t0)],
            remoteIsComplete: false,
            tracked: ["a": local("a", body: "edited")],
            untracked: [],
            ledger: ["a": entry("old", updatedAt: t0)]
        )
        XCTAssertEqual(plan.push, ["a"])
    }

    func test_remoteEdit_isPulled_whenLocalUnchanged() {
        let plan = ChangeSet.compute(
            remote: ["a": remote("a", content: "new", updatedAt: t1)],
            remoteIsComplete: false,
            tracked: ["a": local("a", body: "old")],
            untracked: [],
            ledger: ["a": entry("old", updatedAt: t0)]
        )
        XCTAssertEqual(plan.pull, ["a"])
    }

    func test_bothEdited_isConflict() {
        let plan = ChangeSet.compute(
            remote: ["a": remote("a", content: "server", updatedAt: t1)],
            remoteIsComplete: false,
            tracked: ["a": local("a", body: "mine")],
            untracked: [],
            ledger: ["a": entry("base", updatedAt: t0)]
        )
        XCTAssertEqual(plan.conflict, ["a"])
    }

    func test_inSyncNoBaseline_adoptsWithoutConflict() {
        // Content already identical but ledger was reset → adopt, never conflict.
        let body = "same"
        let plan = ChangeSet.compute(
            remote: ["a": remote("a", content: body, updatedAt: t0)],
            remoteIsComplete: false,
            tracked: ["a": local("a", body: body)],
            untracked: [],
            ledger: [:]
        )
        XCTAssertEqual(plan.adopt, ["a"])
        XCTAssertTrue(plan.conflict.isEmpty)
        XCTAssertTrue(plan.pull.isEmpty)
    }

    func test_localDeleted_deletesRemote() {
        let plan = ChangeSet.compute(
            remote: [:], remoteIsComplete: false, tracked: [:], untracked: [],
            ledger: ["a": entry("old", updatedAt: t0)]
        )
        XCTAssertEqual(plan.deleteRemote, ["a"])
    }

    func test_remoteDeletedTombstone_deletesLocal() {
        let plan = ChangeSet.compute(
            remote: ["a": remote("a", content: "", updatedAt: t1, deleted: true)],
            remoteIsComplete: false,
            tracked: ["a": local("a", body: "old")],
            untracked: [],
            ledger: ["a": entry("old", updatedAt: t0)]
        )
        XCTAssertEqual(plan.deleteLocal, ["a"])
    }

    func test_fullReconcile_absentRemote_deletesLocal() {
        // Not tombstoned, just absent from a complete listing → deletion.
        let plan = ChangeSet.compute(
            remote: [:], remoteIsComplete: true,
            tracked: ["a": local("a", body: "old")],
            untracked: [],
            ledger: ["a": entry("old", updatedAt: t0)]
        )
        XCTAssertEqual(plan.deleteLocal, ["a"])
    }

    func test_deltaCycle_absentRemote_doesNotDeleteUnchangedLocal() {
        // Delta mode: an id not present just means unchanged, not deleted.
        let plan = ChangeSet.compute(
            remote: [:], remoteIsComplete: false,
            tracked: ["a": local("a", body: "old")],
            untracked: [],
            ledger: ["a": entry("old", updatedAt: t0)]
        )
        XCTAssertEqual(plan.noOp, ["a"])
        XCTAssertTrue(plan.deleteLocal.isEmpty)
    }
}
