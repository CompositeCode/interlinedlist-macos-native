import XCTest
@testable import InterlinedListSyncCore

final class ModelsTests: XCTestCase {

    private let decoder = JSONCoding.makeDecoder()

    // MARK: - Date parsing

    func test_parseISO8601_withFractionalSeconds() {
        let date = JSONCoding.parseISO8601("2026-06-20T14:00:00.000Z")
        XCTAssertNotNil(date)
    }

    func test_parseISO8601_withoutFractionalSeconds() {
        let date = JSONCoding.parseISO8601("2026-06-20T14:00:00Z")
        XCTAssertNotNil(date)
    }

    func test_iso8601String_roundTrips() {
        let original = JSONCoding.parseISO8601("2026-06-20T14:00:00.500Z")!
        let string = JSONCoding.iso8601String(original)
        let parsed = JSONCoding.parseISO8601(string)!
        XCTAssertEqual(original.timeIntervalSince1970, parsed.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - RemoteDocument

    func test_remoteDocument_decodesFullDetail() throws {
        let json = """
        {
            "id": "abc123",
            "title": "My Document",
            "content": "# Hello\\n\\nBody.",
            "folderId": "folder-1",
            "updatedAt": "2026-06-20T14:00:00.000Z",
            "createdAt": "2026-06-01T09:00:00.000Z",
            "isPublic": false,
            "contentHash": "deadbeef"
        }
        """
        let doc = try decoder.decode(RemoteDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.id, "abc123")
        XCTAssertEqual(doc.title, "My Document")
        XCTAssertEqual(doc.content, "# Hello\n\nBody.")
        XCTAssertEqual(doc.folderId, "folder-1")
        XCTAssertEqual(doc.isPublic, false)
    }

    func test_remoteDocument_decodesMetadataOnly_missingContentAndDates() throws {
        // List responses omit content; a missing updatedAt must not fail.
        let json = """
        { "id": "x", "title": "Bare", "folderId": null }
        """
        let doc = try decoder.decode(RemoteDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.id, "x")
        XCTAssertNil(doc.content)
        XCTAssertNil(doc.folderId)
        XCTAssertEqual(doc.updatedAt, Date(timeIntervalSince1970: 0))
    }

    // MARK: - Delta

    func test_deltaResponse_decodesTombstoneAndFolders() throws {
        let json = """
        {
            "lastSyncAt": "2026-06-22T10:05:00.000Z",
            "documents": [
                { "id": "d1", "title": "Kept", "content": "x", "updatedAt": "2026-06-22T09:00:00.000Z" },
                { "id": "d2", "title": "Gone", "updatedAt": "2026-06-22T09:30:00.000Z", "deletedAt": "2026-06-22T09:31:00.000Z" }
            ],
            "folders": [
                { "id": "f1", "name": "Notes", "parentId": null }
            ]
        }
        """
        let delta = try decoder.decode(DeltaResponse.self, from: Data(json.utf8))
        XCTAssertNotNil(delta.lastSyncAt)
        XCTAssertEqual(delta.documents.count, 2)
        XCTAssertFalse(delta.documents[0].isDeleted)
        XCTAssertTrue(delta.documents[1].isDeleted)
        XCTAssertEqual(delta.folders.first?.name, "Notes")
    }

    func test_deltaResponse_toleratesSyncedAtAlias_andEmptyArrays() throws {
        let json = """
        { "syncedAt": "2026-06-22T10:05:00.000Z" }
        """
        let delta = try decoder.decode(DeltaResponse.self, from: Data(json.utf8))
        XCTAssertNotNil(delta.lastSyncAt)
        XCTAssertTrue(delta.documents.isEmpty)
        XCTAssertTrue(delta.folders.isEmpty)
    }

    // MARK: - Envelopes & token

    func test_documentEnvelope_decodesWrappedObject() throws {
        let json = """
        { "document": { "id": "n", "title": "New", "content": "hi", "updatedAt": "2026-06-22T10:00:00.000Z" }, "message": "created" }
        """
        let env = try decoder.decode(DocumentEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(env.document?.id, "n")
        XCTAssertEqual(env.message, "created")
    }

    func test_syncTokenResponse_decodesTokenAndLegacyAliases() throws {
        let current = try decoder.decode(SyncTokenResponse.self, from: Data(#"{"token":"il_tok_abc"}"#.utf8))
        XCTAssertEqual(current.token, "il_tok_abc")

        let legacy = try decoder.decode(SyncTokenResponse.self, from: Data(#"{"accessToken":"il_tok_xyz"}"#.utf8))
        XCTAssertEqual(legacy.token, "il_tok_xyz")
    }
}
