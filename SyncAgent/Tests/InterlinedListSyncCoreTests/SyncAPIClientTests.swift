import XCTest
@testable import InterlinedListSyncCore

/// Intercepts URLSession traffic so the client can be tested without a network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

final class SyncAPIClientTests: XCTestCase {

    private func makeClient(token: String? = "il_tok_test") -> SyncAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return SyncAPIClient(
            baseURL: URL(string: "https://interlinedlist.com")!,
            tokenProvider: StaticTokenProvider(token),
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func test_fetchDelta_sendsBearerAndLastSyncAt_andDecodes() async throws {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer il_tok_test")
            XCTAssertEqual(request.url?.path, "/api/documents/sync")
            XCTAssertTrue(request.url?.query?.contains("lastSyncAt=") ?? false)
            let (r, d) = (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                          Data(#"{"lastSyncAt":"2026-01-01T00:00:00.000Z","documents":[{"id":"a","title":"A","content":"x","updatedAt":"2026-01-01T00:00:00.000Z"}],"folders":[]}"#.utf8))
            return (r, d)
        }
        let client = makeClient()
        let delta = try await client.fetchDelta(since: since)
        XCTAssertEqual(delta.documents.first?.id, "a")
    }

    func test_createDocument_decodesEnvelope() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let json = #"{"document":{"id":"new","title":"New","content":"hi","updatedAt":"2026-01-01T00:00:00.000Z"},"message":"created"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let client = makeClient()
        let doc = try await client.createDocument(CreateDocumentBody(title: "New", content: "hi"))
        XCTAssertEqual(doc.id, "new")
    }

    func test_missingToken_throwsNoToken() async {
        let client = makeClient(token: nil)
        do {
            _ = try await client.fetchAllDocuments()
            XCTFail("expected noToken")
        } catch {
            XCTAssertEqual(error as? APIError, .noToken)
        }
    }

    func test_401_mapsToUnauthorized() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.fetchDelta(since: nil)
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func test_delete_treats404AsSuccess() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = makeClient()
        try await client.deleteDocument(id: "gone") // must not throw
    }
}
