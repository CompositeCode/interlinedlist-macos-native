import XCTest
@testable import InterlinedListSyncCore

final class DocumentMapperTests: XCTestCase {

    private var root: URL!
    private var mapper: DocumentMapper!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iltest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        mapper = DocumentMapper(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_place_writesFileWithXattrID() throws {
        let url = try mapper.place(id: "doc-1", title: "My Note", content: "# Hi", folderRelativePath: "", currentURL: nil)
        XCTAssertEqual(url.lastPathComponent, "My Note.md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Hi")
        XCTAssertEqual(mapper.documentID(at: url), "doc-1")
    }

    func test_place_mirrorsFolderPath() throws {
        let url = try mapper.place(id: "d", title: "Nested", content: "x", folderRelativePath: "Projects/Alpha", currentURL: nil)
        XCTAssertTrue(url.path.contains("/Projects/Alpha/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_place_renamesWhenTitleChanges() throws {
        let first = try mapper.place(id: "d", title: "Old Title", content: "x", folderRelativePath: "", currentURL: nil)
        let second = try mapper.place(id: "d", title: "New Title", content: "y", folderRelativePath: "", currentURL: first)
        XCTAssertEqual(second.lastPathComponent, "New Title.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(mapper.documentID(at: second), "d")
    }

    func test_place_disambiguatesTitleCollisionAcrossDifferentIDs() throws {
        let a = try mapper.place(id: "id-a", title: "Same", content: "a", folderRelativePath: "", currentURL: nil)
        let b = try mapper.place(id: "id-bbbbbb", title: "Same", content: "b", folderRelativePath: "", currentURL: nil)
        XCTAssertNotEqual(a.lastPathComponent, b.lastPathComponent)
        XCTAssertEqual(mapper.documentID(at: a), "id-a")
        XCTAssertEqual(mapper.documentID(at: b), "id-bbbbbb")
    }

    func test_sanitizeFilename_stripsIllegalCharacters() {
        XCTAssertEqual(mapper.sanitizeFilename("a/b:c?"), "a-b-c-")
        XCTAssertEqual(mapper.sanitizeFilename(""), "Untitled")
        XCTAssertEqual(mapper.sanitizeFilename(".hidden"), "hidden")
    }

    func test_writeConflictCopy_createsSiblingAndPreservesOriginal() throws {
        let original = try mapper.place(id: "d", title: "Doc", content: "remote", folderRelativePath: "", currentURL: nil)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let copy = try mapper.writeConflictCopy(of: original, body: "my local edits", at: date)
        XCTAssertTrue(copy.lastPathComponent.contains(".conflict-"))
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "my local edits")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "remote")
    }

    func test_scan_separatesTrackedFromUntracked_andSkipsConflictCopies() throws {
        // Tracked file (has xattr id).
        _ = try mapper.place(id: "tracked-1", title: "Tracked", content: "t", folderRelativePath: "Folder", currentURL: nil)
        // Untracked file (plain write, no xattr).
        let untrackedURL = root.appendingPathComponent("Loose.md")
        try "loose".write(to: untrackedURL, atomically: true, encoding: .utf8)
        // Conflict copy (must be ignored).
        _ = try mapper.writeConflictCopy(of: untrackedURL, body: "conf", at: Date(timeIntervalSince1970: 1))

        let scanned = try mapper.scan()
        let tracked = scanned.filter { $0.isTracked }
        let untracked = scanned.filter { !$0.isTracked }

        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked.first?.documentID, "tracked-1")
        XCTAssertEqual(tracked.first?.folderRelativePath, "Folder")
        XCTAssertEqual(untracked.count, 1)
        XCTAssertEqual(untracked.first?.title, "Loose")
        XCTAssertFalse(scanned.contains { $0.url.lastPathComponent.contains(".conflict-") })
    }
}
