import XCTest
@testable import InterlinedKit

/// BDD tests for the Search endpoint group (the-gaps.md G5).
final class SearchEndpointTests: XCTestCase {

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

    private func messageJSON(id: String, content: String) -> String {
        #"""
        {"id":"\#(id)","content":"\#(content)","publiclyVisible":true,"userId":"u-1",
         "createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z",
         "digCount":0,"pushCount":0,"dugByMe":false,
         "user":{"id":"u-1","username":"ada","displayName":"Ada"}}
        """#
    }

    // MARK: - Builder shape assertions

    func test_givenSearchBuilders_whenConstructed_thenUseExpectedMethodPathAuthAndQuery() {
        let m = Search.messages(query: "hello", limit: 10, offset: 5)
        XCTAssertEqual(m.method, .get)
        XCTAssertEqual(m.path, "/api/messages/search")
        XCTAssertEqual(m.auth, .bearer)
        XCTAssertEqual(m.query.first(where: { $0.name == "q" })?.value, "hello")
        XCTAssertEqual(m.query.first(where: { $0.name == "limit" })?.value, "10")
        XCTAssertEqual(m.query.first(where: { $0.name == "offset" })?.value, "5")

        XCTAssertEqual(Search.lists(query: "x").path, "/api/lists/search")
        XCTAssertEqual(Search.lists(query: "x").method, .get)
        XCTAssertEqual(Search.documents(query: "x").path, "/api/documents/search")
        XCTAssertEqual(Search.documents(query: "x").method, .get)
    }

    // MARK: - Happy path

    func test_givenMessagesBody_whenSearchSent_thenDecodesMessagesAndSendsQuery() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"messages":[\#(messageJSON(id: "m1", content: "hello world"))]}"#))

        let response = try await client.send(Search.messages(query: "hello"))

        XCTAssertEqual(response.messages.map(\.id), ["m1"])
        XCTAssertNil(response.pagination)
        let received = await transport.received
        let comps = URLComponents(url: try XCTUnwrap(received[0].url), resolvingAgainstBaseURL: false)
        XCTAssertTrue(comps?.queryItems?.contains(URLQueryItem(name: "q", value: "hello")) ?? false)
    }

    func test_givenListsBodyWithPagination_whenSearchSent_thenDecodesListsAndPagination() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"lists":[{"id":"l1","title":"Bikes"}],
         "pagination":{"total":1,"limit":20,"offset":0,"hasMore":false}}
        """#))

        let response = try await client.send(Search.lists(query: "bike"))

        XCTAssertEqual(response.lists.map(\.id), ["l1"])
        XCTAssertEqual(response.pagination?.total, 1)
    }

    func test_givenDocumentsBody_whenSearchSent_thenDecodesDocuments() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"documents":[{"id":"d1","title":"Notes","content":"body"}]}"#))

        let response = try await client.send(Search.documents(query: "notes"))

        XCTAssertEqual(response.documents.map(\.id), ["d1"])
    }

    // MARK: - API failure

    func test_givenServerError_whenSearchSent_thenThrowsHttpStatus() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"boom"}"#, status: 500))

        do {
            _ = try await client.send(Search.messages(query: "hello"))
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoHits_whenSearchSent_thenReturnsEmptyCollection() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"lists":[],"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#))

        let response = try await client.send(Search.lists(query: "zzz"))

        XCTAssertTrue(response.lists.isEmpty)
    }

    func test_givenMalformedBody_whenSearchSent_thenThrowsDecodingError() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"messages":"not-an-array"}"#))

        do {
            _ = try await client.send(Search.messages(query: "hello"))
            XCTFail("Expected decoding error")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }
}
