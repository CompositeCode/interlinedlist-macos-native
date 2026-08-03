import XCTest
@testable import InterlinedKit

final class FileLogTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLogTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_givenAppend_whenFlushed_thenLineIsWrittenToFile() throws {
        let log = FileLog(directory: tempDir, fileName: "test.log")
        let url = try XCTUnwrap(log.currentFileURL)

        log.append(level: .error, category: "APIClient", message: "Decode failed [/api/lists]")

        let contents = try waitForFileContents(at: url, containing: "Decode failed")
        XCTAssertTrue(contents.contains("[ERROR]"))
        XCTAssertTrue(contents.contains("APIClient:"))
        XCTAssertTrue(contents.contains("Decode failed [/api/lists]"))
    }

    func test_givenDisabledDirectory_whenAppend_thenNoOp() throws {
        // nil directory (the XCTest / no-Library case) must never throw or write.
        let log = FileLog(directory: nil)
        XCTAssertNil(log.currentFileURL)
        log.append(level: .error, category: "APIClient", message: "should be dropped")
        // Nothing to assert beyond "did not crash"; the log is a no-op sink.
    }

    func test_givenFileOverMaxBytes_whenAppend_thenRotatesToBackup() throws {
        // Tiny cap so a couple of writes trip rotation deterministically.
        let log = FileLog(directory: tempDir, fileName: "test.log", maxBytes: 64)
        let url = try XCTUnwrap(log.currentFileURL)
        let backup = url.appendingPathExtension("1")

        // First write creates the active file and pushes it past the cap.
        log.append(level: .info, category: "T", message: String(repeating: "x", count: 128))
        _ = try waitForFileContents(at: url, containing: "xxxx")

        // Second write sees the oversized active file and rotates it to `.1`
        // before writing the fresh line.
        log.append(level: .info, category: "T", message: "after-rotation")
        let active = try waitForFileContents(at: url, containing: "after-rotation")

        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path),
                      "previous generation should be preserved as test.log.1")
        XCTAssertFalse(active.contains(String(repeating: "x", count: 128)),
                       "rotated content should no longer be in the active file")
    }

    // MARK: - Helpers

    /// Writes are dispatched asynchronously onto the logger's serial queue, so
    /// poll briefly until the file contains the expected marker.
    private func waitForFileContents(
        at url: URL,
        containing marker: String,
        timeout: TimeInterval = 2.0
    ) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url) {
                let text = String(decoding: data, as: UTF8.self)
                if text.contains(marker) { return text }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
