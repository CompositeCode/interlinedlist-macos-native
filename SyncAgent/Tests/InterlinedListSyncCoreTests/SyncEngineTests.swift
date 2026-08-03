import XCTest
@testable import InterlinedListSyncCore

final class SyncEngineTests: XCTestCase {

    private var root: URL!
    private var mapper: DocumentMapper!
    private var server: FakeServer!
    private var ledger: InMemoryLedgerStore!
    private let fixedNow = Date(timeIntervalSince1970: 2_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iltest-engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        mapper = DocumentMapper(rootURL: root)
        server = FakeServer()
        ledger = InMemoryLedgerStore()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeEngine() -> SyncEngine {
        SyncEngine(api: server, mapper: mapper, ledgerStore: ledger, now: { [fixedNow] in fixedNow })
    }

    private func fileURL(named name: String, in folder: String = "") -> URL {
        let dir = folder.isEmpty ? root! : root.appendingPathComponent(folder)
        return dir.appendingPathComponent(name)
    }

    // MARK: - Pull

    func test_initialSync_pullsRemoteDocumentsToDisk() async throws {
        await server.seedFolder(id: "f1", name: "Notes")
        await server.seedDocument(id: "a", title: "Alpha", content: "# Alpha", folderId: nil)
        await server.seedDocument(id: "b", title: "Beta", content: "# Beta", folderId: "f1")

        let engine = makeEngine()
        let summary = try await engine.runCycle()

        XCTAssertEqual(summary.pulled, 2)
        let alpha = fileURL(named: "Alpha.md")
        XCTAssertEqual(try String(contentsOf: alpha, encoding: .utf8), "# Alpha")
        XCTAssertEqual(mapper.documentID(at: alpha), "a")
        // Folder mirrored.
        let beta = fileURL(named: "Beta.md", in: "Notes")
        XCTAssertEqual(try String(contentsOf: beta, encoding: .utf8), "# Beta")
    }

    // MARK: - Push

    func test_localEdit_pushesToServer() async throws {
        await server.seedDocument(id: "a", title: "Alpha", content: "original")
        let engine = makeEngine()
        try await engine.runCycle()

        // Edit the local file, then sync again.
        let url = fileURL(named: "Alpha.md")
        try "locally edited".write(to: url, atomically: true, encoding: .utf8)
        let summary = try await engine.runCycle()

        XCTAssertEqual(summary.pushed, 1)
        let remote = await server.document(id: "a")
        XCTAssertEqual(remote?.content, "locally edited")
    }

    // MARK: - Create

    func test_newLocalFile_createsRemoteDocument_andAdoptsID() async throws {
        let engine = makeEngine()
        try await engine.runCycle() // establish baseline (empty)

        let url = fileURL(named: "Fresh.md")
        try "brand new".write(to: url, atomically: true, encoding: .utf8)
        let summary = try await engine.runCycle()

        XCTAssertEqual(summary.created, 1)
        let created = await server.createdBodies
        XCTAssertEqual(created, ["brand new"])
        // The local file now carries the server-assigned id.
        XCTAssertNotNil(mapper.documentID(at: url))
    }

    // MARK: - Remote edit

    func test_remoteEdit_pullsDownToDisk() async throws {
        await server.seedDocument(id: "a", title: "Alpha", content: "v1")
        let engine = makeEngine()
        try await engine.runCycle()

        await server.serverEdit(id: "a", content: "v2 from server")
        let summary = try await engine.runCycle()

        XCTAssertEqual(summary.pulled, 1)
        XCTAssertEqual(try String(contentsOf: fileURL(named: "Alpha.md"), encoding: .utf8), "v2 from server")
    }

    // MARK: - Conflict

    func test_simultaneousEdits_createConflictCopy_andRemoteWins() async throws {
        await server.seedDocument(id: "a", title: "Alpha", content: "base")
        let engine = makeEngine()
        try await engine.runCycle()

        // Edit both sides before the next sync.
        let url = fileURL(named: "Alpha.md")
        try "my local change".write(to: url, atomically: true, encoding: .utf8)
        await server.serverEdit(id: "a", content: "server change")

        let summary = try await engine.runCycle()

        XCTAssertEqual(summary.conflicts, 1)
        // Remote wins the canonical file.
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "server change")
        // Local edits preserved in a conflict copy.
        let siblings = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let conflictCopy = siblings.first { $0.contains(".conflict-") }
        XCTAssertNotNil(conflictCopy)
        let copyBody = try String(contentsOf: root.appendingPathComponent(conflictCopy!), encoding: .utf8)
        XCTAssertEqual(copyBody, "my local change")
    }

    // MARK: - Deletions

    func test_localDelete_deletesRemoteDocument() async throws {
        await server.seedDocument(id: "a", title: "Alpha", content: "x")
        let engine = makeEngine()
        try await engine.runCycle()

        try FileManager.default.removeItem(at: fileURL(named: "Alpha.md"))
        let summary = try await engine.runCycle()

        XCTAssertEqual(summary.deletedRemote, 1)
        let remote = await server.document(id: "a")
        XCTAssertNil(remote)
    }

    func test_remoteDelete_viaTombstone_removesLocalFile() async throws {
        await server.seedDocument(id: "a", title: "Alpha", content: "x")
        let engine = makeEngine()
        try await engine.runCycle()

        await server.serverDelete(id: "a")
        let summary = try await engine.runCycle()

        XCTAssertEqual(summary.deletedLocal, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL(named: "Alpha.md").path))
    }

    func test_remoteDelete_withoutTombstone_caughtByFullReconcile() async throws {
        await server.setDeliverTombstones(false)
        await server.seedDocument(id: "a", title: "Alpha", content: "x")
        let engine = makeEngine()
        try await engine.runCycle()

        await server.serverDelete(id: "a")
        // Delta cycle won't see it; force the full-list safety net.
        let summary = try await engine.runCycle(forceFullReconcile: true)

        XCTAssertEqual(summary.deletedLocal, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL(named: "Alpha.md").path))
    }

    // MARK: - Idempotence

    func test_secondCycle_withNoChanges_isNoOp() async throws {
        await server.seedDocument(id: "a", title: "Alpha", content: "x")
        let engine = makeEngine()
        try await engine.runCycle()
        let summary = try await engine.runCycle()
        XCTAssertEqual(summary.changeCount, 0)
    }
}
