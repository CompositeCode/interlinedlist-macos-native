import XCTest
@testable import InterlinedKit

/// BDD tests for the List Folders endpoint group (work-consolidation.md G6).
final class ListFoldersEndpointTests: XCTestCase {

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

    func test_givenListFolderBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(ListFolders.list().path, "/api/folders")
        XCTAssertEqual(ListFolders.list().method, .get)
        XCTAssertEqual(ListFolders.list().auth, .bearer)

        XCTAssertEqual(ListFolders.create(CreateListFolderRequest(name: "A")).method, .post)
        XCTAssertEqual(ListFolders.create(CreateListFolderRequest(name: "A")).path, "/api/folders")

        XCTAssertEqual(ListFolders.update(id: "f1", UpdateListFolderRequest(name: "B")).method, .put)
        XCTAssertEqual(ListFolders.update(id: "f1", UpdateListFolderRequest(name: "B")).path, "/api/folders/f1")

        XCTAssertEqual(ListFolders.delete(id: "f1").method, .delete)
        XCTAssertEqual(ListFolders.delete(id: "f1").path, "/api/folders/f1")
    }

    // MARK: - Happy path

    func test_givenFoldersBody_whenListSent_thenDecodesFolders() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"folders":[
          {"id":"f1","name":"Root","parentId":null},
          {"id":"f2","name":"Child","parentId":"f1"}
        ]}
        """#))

        let response = try await client.send(ListFolders.list())

        XCTAssertEqual(response.folders.map(\.id), ["f1", "f2"])
        XCTAssertEqual(response.folders.last?.parentId, "f1")
    }

    func test_givenCreateBody_whenCreateSent_thenEncodesNameAndDecodesFolder() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"id":"f9","name":"New Folder","parentId":null}"#))

        let folder = try await client.send(ListFolders.create(CreateListFolderRequest(name: "New Folder")))

        XCTAssertEqual(folder.id, "f9")
        let received = await transport.received
        let body = try XCTUnwrap(received[0].httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "New Folder")
    }

    // MARK: - API failure

    func test_givenForbidden_whenCreateSent_thenThrowsForbidden() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"subscriber required"}"#, status: 403))

        do {
            _ = try await client.send(ListFolders.create(CreateListFolderRequest(name: "A")))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "subscriber required"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoFolders_whenListSent_thenReturnsEmpty() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"folders":[]}"#))

        let response = try await client.send(ListFolders.list())

        XCTAssertTrue(response.folders.isEmpty)
    }
}
