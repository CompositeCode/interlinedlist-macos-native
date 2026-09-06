import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD coverage for `TagsService` + the `TrendingTag` mapper
/// (work-consolidation.md G20).
final class TagsServiceTests: XCTestCase {

    // MARK: - Happy path

    func test_givenTrendingBody_whenFetching_thenMapsNamesAndCounts() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "tags": [ { "tag": "swift", "count": 42, "lastUsedAt": "2026-09-05T12:00:00Z" },
                    { "tag": "swiftui", "count": 17 } ] }
        """#)
        let service = TagsService(api: api)

        let tags = try await service.trending()

        XCTAssertEqual(tags.map(\.name), ["swift", "swiftui"])
        XCTAssertEqual(tags[0].count, 42)
        XCTAssertNotNil(tags[0].lastUsedAt)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/tags/trending")
    }

    func test_givenPrefix_whenSuggesting_thenReturnsNames() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "tags": [ "swift", "swiftui" ] }"#)
        let service = TagsService(api: api)

        let names = try await service.suggestions(prefix: "swi")

        XCTAssertEqual(names, ["swift", "swiftui"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/tags/autocomplete")
    }

    // MARK: - Invalid input

    func test_givenHashPrefixedTags_whenMapping_thenStripsLeadingHash() async throws {
        let api = StubAPIClient()
        // `##"…"##` because the payload contains `"#`, which would close a `#"…"#`.
        await api.enqueue(json: ##"{ "tags": [ { "tag": "#swift" }, { "tag": "  spaced  " } ] }"##)
        let service = TagsService(api: api)

        let tags = try await service.trending()

        // The UI renders its own `#`, so a server-supplied one must not survive.
        XCTAssertEqual(tags.map(\.name), ["swift", "spaced"])
        XCTAssertEqual(tags[0].count, 0, "missing count collapses to 0")
    }

    func test_givenBlankPrefix_whenSuggesting_thenSkipsTheRequestEntirely() async throws {
        let api = StubAPIClient()
        let service = TagsService(api: api)

        let names = try await service.suggestions(prefix: "   ")

        XCTAssertTrue(names.isEmpty)
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "a blank prefix must not ask the server to rank every tag")
    }

    // MARK: - Upstream failure

    func test_givenServerFailure_whenFetchingTrending_thenThrows() async {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 503, serverMessage: nil))
        let service = TagsService(api: api)

        do {
            _ = try await service.trending()
            XCTFail("Expected the failure to propagate")
        } catch {
            // expected
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoTags_whenFetching_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "tags": [] }"#)
        let service = TagsService(api: api)

        let tags = try await service.trending()

        XCTAssertTrue(tags.isEmpty)
    }
}
