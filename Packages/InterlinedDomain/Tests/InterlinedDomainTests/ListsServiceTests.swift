import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `ListsService` (M1 task 1B — PLAN.md §1 "Public
/// list browsing", §6 M1, §7 testing).
///
/// Minimum coverage per behavior per PLAN.md §7: happy path, invalid input
/// (boundary username), upstream API failure, and empty/boundary page.
final class ListsServiceTests: XCTestCase {

    // MARK: - publicLists

    func test_givenUserHasLists_whenLoadingPublicLists_thenMapsPageAndCursor() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(
            ids: ["list-1", "list-2"],
            total: 40,
            limit: 20,
            offset: 0,
            hasMore: true
        ))
        let service = ListsService(api: api)

        // When
        let page = try await service.publicLists(username: "ada", limit: 20, offset: 0)

        // Then
        XCTAssertEqual(page.lists.map(\.id), ["list-1", "list-2"])
        XCTAssertEqual(page.lists.first?.title, "Books")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 20)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/users/ada/lists")
        XCTAssertEqual(recorded.first?.query["limit"], "20")
        XCTAssertEqual(recorded.first?.query["offset"], "0")
    }

    func test_givenUserHasNoLists_whenLoadingPublicLists_thenReturnsEmptyPage() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(ids: [], total: 0, hasMore: false))
        let service = ListsService(api: api)

        // When
        let page = try await service.publicLists(username: "stranger", limit: 20, offset: 0)

        // Then
        XCTAssertTrue(page.lists.isEmpty)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    func test_givenAPIFailure_whenLoadingPublicLists_thenThrows() async throws {
        // Given — public endpoint returning a transport error.
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.publicLists(username: "ada", limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport(message: "offline"))
        }
    }

    func test_givenUnknownUsername_whenLoadingPublicLists_thenSurfacesNotFound() async throws {
        // Given — invalid input case: a non-existent username yields 404.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "user not found"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.publicLists(username: "ghost", limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "user not found"))
        }
    }

    // MARK: - publicList (detail)

    func test_givenListExists_whenLoadingPublicList_thenMapsDetailAndSchema() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listObject(
            id: "books",
            title: "Books",
            description: "Things I have read",
            isPublic: true,
            schema: "Title:text, Year:number"
        ))
        let service = ListsService(api: api)

        // When
        let detail = try await service.publicList(username: "ada", slug: "books")

        // Then
        XCTAssertEqual(detail.id, "books")
        XCTAssertEqual(detail.title, "Books")
        XCTAssertEqual(detail.schemaDescription, "Title:text, Year:number")
        XCTAssertEqual(detail.visibility, .public)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/users/ada/lists/books")
    }

    func test_givenListMissingSchema_whenLoadingPublicList_thenSchemaDescriptionIsNil() async throws {
        // Given — boundary: list with no schema defined yet.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listObject(id: "raw", schema: nil))
        let service = ListsService(api: api)

        // When
        let detail = try await service.publicList(username: "ada", slug: "raw")

        // Then
        XCTAssertNil(detail.schemaDescription)
        XCTAssertEqual(detail.id, "raw")
    }

    func test_givenListNotFound_whenLoadingPublicList_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no such list"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.publicList(username: "ada", slug: "missing")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no such list"))
        }
    }

    // MARK: - publicRows

    func test_givenListHasRows_whenLoadingPublicRows_thenMapsRowsAndCells() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedRows(
            ids: ["row-1", "row-2"],
            total: 2,
            limit: 20,
            offset: 0,
            hasMore: false
        ))
        let service = ListsService(api: api)

        // When
        let page = try await service.publicRows(
            username: "ada",
            slug: "books",
            limit: 20,
            offset: 0
        )

        // Then
        XCTAssertEqual(page.rows.map(\.id), ["row-1", "row-2"])
        XCTAssertEqual(page.rows.first?.fields["Title"], .string("Dune"))
        XCTAssertEqual(page.rows.first?.fields["Year"], .int(1965))
        XCTAssertFalse(page.hasMore)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/users/ada/lists/books/data")
    }

    func test_givenListHasNoRows_whenLoadingPublicRows_thenReturnsEmptyPage() async throws {
        // Given — boundary: an empty list.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedRows(ids: [], total: 0, hasMore: false))
        let service = ListsService(api: api)

        // When
        let page = try await service.publicRows(
            username: "ada",
            slug: "empty",
            limit: 20,
            offset: 0
        )

        // Then
        XCTAssertTrue(page.rows.isEmpty)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    func test_givenAPIFailure_whenLoadingPublicRows_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .rateLimited(serverMessage: "slow down", retryAfter: 5))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.publicRows(
                username: "ada",
                slug: "books",
                limit: 20,
                offset: 0
            )
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .rateLimited(serverMessage: "slow down", retryAfter: 5))
        }
    }

    func test_givenRowsHasMore_whenLoadingPublicRows_thenNextOffsetAdvances() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedRows(
            ids: ["row-1"],
            total: 100,
            limit: 10,
            offset: 20,
            hasMore: true
        ))
        let service = ListsService(api: api)

        // When
        let page = try await service.publicRows(
            username: "ada",
            slug: "books",
            limit: 10,
            offset: 20
        )

        // Then — cursor advances by limit when more pages remain.
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 30)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.query["limit"], "10")
        XCTAssertEqual(recorded.first?.query["offset"], "20")
    }
}
