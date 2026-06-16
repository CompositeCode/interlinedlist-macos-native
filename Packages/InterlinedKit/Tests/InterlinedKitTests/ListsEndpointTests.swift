import XCTest
@testable import InterlinedKit

/// BDD tests for the Lists endpoint group: builder correctness (method, path,
/// query, auth, body) plus client round-trips covering happy path, API
/// failure, and decode/empty/boundary cases against `StubHTTPDataTransport`.
final class ListsEndpointTests: XCTestCase {

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

    func test_givenListBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Lists.list().method, .get)
        XCTAssertEqual(Lists.list().path, "/api/lists")
        XCTAssertEqual(Lists.list().auth, .bearer)
        XCTAssertEqual(Lists.list().paginationKey, "data")

        let create = Lists.create(CreateListRequest(title: "Books"))
        XCTAssertEqual(create.method, .post)
        XCTAssertEqual(create.path, "/api/lists")
        XCTAssertNotNil(create.body)

        XCTAssertEqual(Lists.get(id: "7").path, "/api/lists/7")
        XCTAssertEqual(Lists.update(id: "7", UpdateListRequest(title: "x")).method, .put)
        XCTAssertEqual(Lists.delete(id: "7").method, .delete)

        XCTAssertEqual(Lists.schema(id: "7").path, "/api/lists/7/schema")
        XCTAssertEqual(Lists.updateSchema(id: "7", UpdateListSchemaRequest(schema: "A:text")).method, .put)
        XCTAssertEqual(Lists.refresh(id: "7").method, .post)
        XCTAssertEqual(Lists.refresh(id: "7").path, "/api/lists/7/refresh")

        XCTAssertEqual(Lists.rows(listId: "7").path, "/api/lists/7/data")
        XCTAssertEqual(Lists.rows(listId: "7").paginationKey, "data")
        XCTAssertEqual(Lists.createRow(listId: "7", CreateListRowRequest(rowData: [:])).method, .post)
        XCTAssertEqual(Lists.row(listId: "7", rowId: "r1").path, "/api/lists/7/data/r1")
        XCTAssertEqual(Lists.updateRow(listId: "7", rowId: "r1", UpdateListRowRequest(rowData: [:])).method, .patch)
        XCTAssertEqual(Lists.deleteRow(listId: "7", rowId: "r1").method, .delete)

        XCTAssertEqual(Lists.watchers(listId: "7").path, "/api/lists/7/watchers")
        XCTAssertEqual(Lists.myWatcherStatus(listId: "7").path, "/api/lists/7/watchers/me")
        XCTAssertEqual(Lists.watcherUsers(listId: "7").path, "/api/lists/7/watchers/users")
        XCTAssertEqual(Lists.setWatcher(listId: "7", userId: "u2", UpdateListWatcherRequest(role: "manager")).method, .put)
        XCTAssertEqual(Lists.setWatcher(listId: "7", userId: "u2", UpdateListWatcherRequest(role: "manager")).path, "/api/lists/7/watchers/u2")
        XCTAssertEqual(Lists.removeWatcher(listId: "7", userId: "u2").method, .delete)

        XCTAssertEqual(Lists.connections().path, "/api/lists/connections")
        XCTAssertEqual(Lists.createConnection(CreateListConnectionRequest(fromListId: "a", toListId: "b")).method, .post)
        XCTAssertEqual(Lists.deleteConnection(id: "c1").path, "/api/lists/connections/c1")
        XCTAssertEqual(Lists.deleteConnection(id: "c1").method, .delete)
    }

    func test_givenPublicBuilders_whenConstructed_thenUseNoneAuth() {
        XCTAssertEqual(Lists.publicLists(username: "ada").auth, .none)
        XCTAssertEqual(Lists.publicLists(username: "ada").path, "/api/users/ada/lists")
        XCTAssertEqual(Lists.publicList(username: "ada", id: "7").auth, .none)
        XCTAssertEqual(Lists.publicList(username: "ada", id: "7").path, "/api/users/ada/lists/7")
        XCTAssertEqual(Lists.publicListRows(username: "ada", id: "7").auth, .none)
        XCTAssertEqual(Lists.publicListRows(username: "ada", id: "7").path, "/api/users/ada/lists/7/data")
        XCTAssertEqual(Lists.publicListRows(username: "ada", id: "7").paginationKey, "data")
    }

    func test_givenOptionalQuery_whenListBuilt_thenSkipsNilParameters() {
        let req = Lists.list(limit: 10, offset: nil, page: 2)
        let names = req.query.compactMap { $0.value != nil ? $0.name : nil }
        XCTAssertEqual(Set(names), ["limit", "page"])
    }

    // MARK: - Happy path

    func test_givenPaginatedListEnvelope_whenListSent_thenDecodesItemsUnderDataKey() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"data":[{"id":"1","title":"Books"},{"id":"2","title":"Films"}],
         "pagination":{"total":2,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(ListDTO.self, request: Lists.list(), using: client)

        XCTAssertEqual(page.items.map(\.id), ["1", "2"])
        XCTAssertEqual(page.items.first?.title, "Books")
        XCTAssertFalse(page.pagination.hasMore)

        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "GET")
        XCTAssertEqual(received[0].url?.path, "/api/lists")
        XCTAssertEqual(received[0].value(forHTTPHeaderField: "Authorization"), "Bearer il_tok_abc")
    }

    func test_givenDynamicSchemaRow_whenRowSent_thenDecodesFlexibleRowData() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"id":"r1","listId":"7",
         "rowData":{"Title":"Dune","Year":1965,"Read":true,"Rating":4.5,"Tags":["sci-fi"]}}
        """#))

        let row = try await client.send(Lists.row(listId: "7", rowId: "r1"))

        XCTAssertEqual(row.id, "r1")
        XCTAssertEqual(row.rowData["Title"], .string("Dune"))
        XCTAssertEqual(row.rowData["Year"], .int(1965))
        XCTAssertEqual(row.rowData["Read"], .bool(true))
        XCTAssertEqual(row.rowData["Rating"], .double(4.5))
        XCTAssertEqual(row.rowData["Tags"], .array([.string("sci-fi")]))

        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/lists/7/data/r1")
    }

    func test_givenRowData_whenCreateRowSent_thenEncodesRowDataEnvelope() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"id":"r9","rowData":{"Title":"New"}}"#))

        let body = CreateListRowRequest(rowData: ["Title": .string("New")])
        _ = try await client.send(Lists.createRow(listId: "7", body))

        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "POST")
        let sent = try XCTUnwrap(received[0].httpBody)
        let decoded = try JSONDecoder().decode([String: [String: ListJSONValue]].self, from: sent)
        XCTAssertEqual(decoded["rowData"]?["Title"], .string("New"))
    }

    func test_givenConnectionsEnvelope_whenConnectionsSent_thenDecodesUnderConnectionsKey() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"connections":[{"id":"c1","fromListId":"a","toListId":"b","label":"refs"}]}
        """#))

        let result = try await client.send(Lists.connections())

        XCTAssertEqual(result.connections.count, 1)
        XCTAssertEqual(result.connections.first?.label, "refs")
    }

    // MARK: - API failure

    func test_givenNotFound_whenGetListSent_thenThrowsNotFoundAPIError() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"List not found"}"#, status: 404))

        do {
            _ = try await client.send(Lists.get(id: "missing"))
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "List not found"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenEmptyListEnvelope_whenListSent_thenReturnsNoItems() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"data":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(ListDTO.self, request: Lists.list(), using: client)

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.pagination.total, 0)
    }

    func test_givenEmptyRowData_whenRowSent_thenDecodesEmptyMap() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"id":"r1","rowData":{}}"#))

        let row = try await client.send(Lists.row(listId: "7", rowId: "r1"))

        XCTAssertTrue(row.rowData.isEmpty)
    }

    func test_givenNoContent_whenDeleteListSent_thenSucceeds() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.empty(status: 204))

        try await client.sendVoid(Lists.delete(id: "7"))

        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "DELETE")
        XCTAssertEqual(received[0].url?.path, "/api/lists/7")
    }
}
