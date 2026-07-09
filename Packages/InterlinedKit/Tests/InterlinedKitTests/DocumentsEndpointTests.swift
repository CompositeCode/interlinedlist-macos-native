import XCTest
@testable import InterlinedKit

/// BDD tests for the Documents & Sync endpoint group.
final class DocumentsEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_abc")
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    // MARK: - Builder shape assertions

    func test_givenDocumentBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Documents.sync().path, "/api/documents/sync")
        XCTAssertEqual(Documents.sync().method, .get)
        XCTAssertEqual(Documents.sync().auth, .bearer)
        XCTAssertEqual(Documents.pushSync(DocumentSyncRequest(operations: [])).method, .post)

        XCTAssertEqual(Documents.list().path, "/api/documents")
        XCTAssertEqual(Documents.list().paginationKey, "documents")
        XCTAssertEqual(Documents.create(CreateDocumentRequest(title: "t", content: "c")).method, .post)
        XCTAssertEqual(Documents.get(id: "9").path, "/api/documents/9")
        XCTAssertEqual(Documents.update(id: "9", UpdateDocumentRequest(title: "x")).method, .patch)
        XCTAssertEqual(Documents.delete(id: "9").method, .delete)

        let upload = Documents.uploadImage(id: "9", body: Data("png".utf8), contentType: "multipart/form-data; boundary=X")
        XCTAssertEqual(upload.method, .post)
        XCTAssertEqual(upload.path, "/api/documents/9/images/upload")
        XCTAssertNotNil(upload.body)

        XCTAssertEqual(Documents.folders().path, "/api/documents/folders")
        XCTAssertEqual(Documents.folders().paginationKey, "folders")
        XCTAssertEqual(Documents.createFolder(CreateDocumentFolderRequest(name: "n")).method, .post)
        XCTAssertEqual(Documents.folder(id: "f1").path, "/api/documents/folders/f1")
        XCTAssertEqual(Documents.updateFolder(id: "f1", UpdateDocumentFolderRequest(name: "n")).method, .patch)
        XCTAssertEqual(Documents.deleteFolder(id: "f1").method, .delete)
        XCTAssertEqual(Documents.folderDocuments(id: "f1").path, "/api/documents/folders/f1/documents")
        XCTAssertEqual(Documents.folderDocuments(id: "f1").paginationKey, "documents")
    }

    func test_givenLastSyncAt_whenSyncBuilt_thenAddsQueryParameter() {
        let withCursor = Documents.sync(lastSyncAt: "2026-06-16T00:00:00Z")
        XCTAssertEqual(withCursor.query.first(where: { $0.name == "lastSyncAt" })?.value, "2026-06-16T00:00:00Z")

        let withoutCursor = Documents.sync()
        XCTAssertNil(withoutCursor.query.first(where: { $0.name == "lastSyncAt" })?.value)
    }

    // MARK: - Happy path

    func test_givenSyncDelta_whenSyncSent_thenDecodesFoldersDocumentsAndTombstones() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"syncedAt":"2026-06-16T00:00:00Z",
         "folders":[{"id":"f1","name":"Notes"}],
         "documents":[{"id":"d1","title":"Hello"},{"id":"d2","title":"Gone","deleted":true}]}
        """#))

        let delta = try await client.send(Documents.sync(lastSyncAt: "2026-06-15T00:00:00Z"))

        XCTAssertEqual(delta.folders.map(\.id), ["f1"])
        XCTAssertEqual(delta.documents.count, 2)
        XCTAssertEqual(delta.documents.first(where: { $0.id == "d2" })?.deleted, true)
        XCTAssertNotNil(delta.syncedAt)
    }

    func test_givenDocumentEnvelope_whenListSent_thenDecodesUnderDocumentsKey() async throws {
        let (client, transport) = makeClient()
        // The Documents API returns items under "documents" without a "pagination" envelope.
        await transport.enqueue(.json(#"""
        {"documents":[{"id":"d1","title":"Hello","folderId":"f1"}]}
        """#))

        let request = Documents.list(folderId: "f1")
        let (data, _) = try await client.sendRaw(request)
        let items = try PaginatedDecoder.decodeItems(
            DocumentDTO.self,
            collectionKey: try XCTUnwrap(request.paginationKey),
            from: data
        )

        XCTAssertEqual(items.first?.folderId, "f1")
        let received = await transport.received
        let comps = URLComponents(url: try XCTUnwrap(received[0].url), resolvingAgainstBaseURL: false)
        XCTAssertTrue(comps?.queryItems?.contains(URLQueryItem(name: "folderId", value: "f1")) ?? false)
    }

    func test_givenImageBytes_whenUploadSent_thenForwardsRawBodyAndContentType() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"url":"https://cdn/x.png"}"#))

        let payload = Data("fakepng".utf8)
        let result = try await client.send(
            Documents.uploadImage(id: "9", body: payload, contentType: "multipart/form-data; boundary=ABC")
        )

        XCTAssertEqual(result.url, "https://cdn/x.png")
        let received = await transport.received
        XCTAssertEqual(received[0].httpBody, payload)
        XCTAssertEqual(received[0].value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=ABC")
    }

    func test_givenSyncOperations_whenPushSent_thenEncodesOperationsArray() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"folders":[],"documents":[]}"#))

        let body = DocumentSyncRequest(operations: [
            DocumentSyncOperation(operation: "create", type: "document", title: "T", content: "C")
        ])
        _ = try await client.send(Documents.pushSync(body))

        let received = await transport.received
        let sent = try XCTUnwrap(received[0].httpBody)
        let decoded = try JSONDecoder().decode(DocumentSyncRequest.self, from: sent)
        XCTAssertEqual(decoded.operations.first?.operation, "create")
        XCTAssertEqual(decoded.operations.first?.type, "document")
    }

    // MARK: - API failure

    func test_givenForbidden_whenCreateDocumentSent_thenThrowsForbiddenWithServerMessage() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"subscriber feature"}"#, status: 403))

        do {
            _ = try await client.send(Documents.create(CreateDocumentRequest(title: "t", content: "c")))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "subscriber feature"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenEmptySyncDelta_whenSyncSent_thenReturnsEmptyCollections() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"folders":[],"documents":[]}"#))

        let delta = try await client.send(Documents.sync())

        XCTAssertTrue(delta.folders.isEmpty)
        XCTAssertTrue(delta.documents.isEmpty)
        XCTAssertNil(delta.syncedAt)
    }

    func test_givenNoContent_whenDeleteFolderSent_thenSucceeds() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.empty(status: 204))

        try await client.sendVoid(Documents.deleteFolder(id: "f1"))

        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "DELETE")
        XCTAssertEqual(received[0].url?.path, "/api/documents/folders/f1")
    }
}
