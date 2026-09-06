import XCTest
@testable import InterlinedKit

/// BDD tests for the Tags endpoints (work-consolidation.md G20).
final class TagsEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient() -> (APIClient, StubHTTPDataTransport) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_abc"),
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        return (APIClient(baseURL: baseURL, transport: transport, authTransport: auth), transport)
    }

    // MARK: - Builder shape

    func test_givenTagBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        let trending = Tags.trending()
        XCTAssertEqual(trending.method, .get)
        XCTAssertEqual(trending.path, "/api/tags/trending")
        XCTAssertEqual(trending.auth, .bearer)
        // A nil limit is kept as a valueless QueryItem and dropped when the
        // URL is built, so assert on the value rather than on emptiness.
        XCTAssertNil(trending.query.first { $0.name == "limit" }?.value)

        let autocomplete = Tags.autocomplete(prefix: "swi", limit: 5)
        XCTAssertEqual(autocomplete.method, .get)
        XCTAssertEqual(autocomplete.path, "/api/tags/autocomplete")
        XCTAssertEqual(autocomplete.auth, .bearer)
    }

    func test_givenLimit_whenTrendingBuilt_thenCarriesLimitQuery() {
        // Query assertions go against the builder, matching SharingEndpointTests.
        XCTAssertTrue(Tags.trending(limit: 10).query.contains(.int("limit", 10)))
        XCTAssertTrue(Tags.autocomplete(prefix: "swi").query.contains(.string("q", "swi")))
    }

    // MARK: - Happy path

    func test_givenTrendingBody_whenSent_thenDecodesTagsAndCounts() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "tags": [ { "tag": "swift", "count": 42, "lastUsedAt": "2026-09-05T12:00:00Z" },
                    { "tag": "swiftui", "count": 17 } ] }
        """#))

        let response = try await client.send(Tags.trending())

        XCTAssertEqual(response.tags.map(\.tag), ["swift", "swiftui"])
        XCTAssertEqual(response.tags[0].count, 42)
        XCTAssertNil(response.tags[1].lastUsedAt)
    }

    // MARK: - Invalid / tolerant input
    //
    // The autocomplete shape is unpinned in the gap definition, so all three
    // plausible encodings must collapse to the same `[String]`.

    func test_givenBareStringArray_whenAutocompleteSent_thenDecodes() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"[ "swift", "swiftui" ]"#))

        let response = try await client.send(Tags.autocomplete(prefix: "swi"))

        XCTAssertEqual(response.tags, ["swift", "swiftui"])
    }

    func test_givenWrappedObjectArray_whenAutocompleteSent_thenDecodesToTagNames() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "tags": [ { "tag": "swift" }, { "tag": "swiftui" } ] }"#))

        let response = try await client.send(Tags.autocomplete(prefix: "swi"))

        XCTAssertEqual(response.tags, ["swift", "swiftui"])
    }

    // MARK: - API failure

    func test_givenServerError_whenTrendingSent_thenThrowsHttpStatus() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"nope"}"#, status: 503))

        do {
            _ = try await client.send(Tags.trending())
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            guard case .httpStatus(let code, _) = error else {
                return XCTFail("Expected .httpStatus, got \(error)")
            }
            XCTAssertEqual(code, 503)
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoTags_whenSent_thenReturnsEmpty() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "tags": [] }"#))

        let response = try await client.send(Tags.trending())

        XCTAssertTrue(response.tags.isEmpty)
    }
}
