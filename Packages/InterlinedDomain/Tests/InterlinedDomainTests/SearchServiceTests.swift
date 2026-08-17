import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `SearchService` (work-consolidation.md G5). Quartet per public
/// method: happy + invalid/short-circuit + failure + empty/boundary.
final class SearchServiceTests: XCTestCase {

    private func messageEnvelope(ids: [String]) -> String {
        let rows = ids.map { id in
            #"""
            {"id":"\#(id)","content":"c-\#(id)","publiclyVisible":true,"userId":"u-1",
             "createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z",
             "digCount":0,"pushCount":0,"dugByMe":false,
             "user":{"id":"u-1","username":"ada","displayName":"Ada"}}
            """#
        }.joined(separator: ",")
        return "{\"messages\":[\(rows)]}"
    }

    // MARK: - messages

    func test_givenHits_whenSearchingMessages_thenMapsRowsAndSendsQuery() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: messageEnvelope(ids: ["m1", "m2"]))
        let service = SearchService(api: api)

        let results = try await service.messages(query: "hello")

        XCTAssertEqual(results.map(\.id), ["m1", "m2"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "GET")
        XCTAssertEqual(recorded.first?.path, "/api/messages/search")
        XCTAssertEqual(recorded.first?.query["q"], "hello")
    }

    func test_givenBlankQuery_whenSearchingMessages_thenReturnsEmptyWithoutRequest() async throws {
        let api = StubAPIClient()
        let service = SearchService(api: api)

        let results = try await service.messages(query: "   ")

        XCTAssertTrue(results.isEmpty)
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "A blank query must not hit the network")
    }

    func test_givenServerFailure_whenSearchingMessages_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = SearchService(api: api)

        do {
            _ = try await service.messages(query: "hello")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenNoHits_whenSearchingMessages_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"messages":[]}"#)
        let service = SearchService(api: api)

        let results = try await service.messages(query: "zzz")

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - lists

    func test_givenHits_whenSearchingLists_thenMapsRows() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"lists":[{"id":"l1","title":"Bikes"}],"pagination":{"total":1,"limit":20,"offset":0,"hasMore":false}}"#)
        let service = SearchService(api: api)

        let results = try await service.lists(query: "bike")

        XCTAssertEqual(results.map(\.id), ["l1"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/search")
        XCTAssertEqual(recorded.first?.query["q"], "bike")
    }

    func test_givenBlankQuery_whenSearchingLists_thenReturnsEmptyWithoutRequest() async throws {
        let api = StubAPIClient()
        let service = SearchService(api: api)

        let results = try await service.lists(query: "")

        XCTAssertTrue(results.isEmpty)
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - documents

    func test_givenHits_whenSearchingDocuments_thenMapsRows() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"documents":[{"id":"d1","title":"Notes","content":"body"}]}"#)
        let service = SearchService(api: api)

        let results = try await service.documents(query: "notes")

        XCTAssertEqual(results.map(\.id), ["d1"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents/search")
    }

    func test_givenDocumentSearchFails_whenSearching_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "nope"))
        let service = SearchService(api: api)

        do {
            _ = try await service.documents(query: "notes")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "nope"))
        }
    }

    // MARK: - all (fan-out)

    func test_givenBlankQuery_whenSearchingAll_thenReturnsEmptyWithoutRequest() async throws {
        let api = StubAPIClient()
        let service = SearchService(api: api)

        let results = try await service.all(query: "  \n ")

        XCTAssertEqual(results, .empty)
        XCTAssertTrue(results.isEmpty)
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenEmptyResults_whenBuildingSearchResults_thenIsEmptyAndCountsZero() {
        let results = SearchResults.empty
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(results.totalCount, 0)
    }
}
