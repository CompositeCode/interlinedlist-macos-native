import XCTest
import InterlinedKit
@testable import InterlinedDomain

final class MessagesServiceTests: XCTestCase {

    // MARK: - Timeline: scope → onlyMine mapping

    func test_givenScopeAll_whenLoadingTimeline_thenOnlyMineIsNotSent() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["a"]))
        let service = MessagesService(api: api)

        // When
        _ = try await service.timeline(scope: .all, tag: nil, limit: 20, offset: 0)

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/messages")
        XCTAssertNil(recorded.first?.query["onlyMine"])
    }

    func test_givenScopeMine_whenLoadingTimeline_thenOnlyMineIsTrue() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["a"]))
        let service = MessagesService(api: api)

        // When
        _ = try await service.timeline(scope: .mine, tag: nil, limit: 20, offset: 0)

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.query["onlyMine"], "true")
    }

    func test_givenTagFilter_whenLoadingTimeline_thenTagAndPagingAreSent() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["a"], limit: 10, offset: 30))
        let service = MessagesService(api: api)

        // When
        _ = try await service.timeline(scope: .all, tag: "swift", limit: 10, offset: 30)

        // Then
        let query = await api.recorded.first?.query
        XCTAssertEqual(query?["tag"], "swift")
        XCTAssertEqual(query?["limit"], "10")
        XCTAssertEqual(query?["offset"], "30")
    }

    // MARK: - Timeline: happy path / pagination / boundary

    func test_givenMessagesAndHasMore_whenLoadingTimeline_thenMapsPageAndCursor() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["a", "b"], total: 40, limit: 20, offset: 0, hasMore: true))
        let service = MessagesService(api: api)

        // When
        let page = try await service.timeline(scope: .all, tag: nil, limit: 20, offset: 0)

        // Then
        XCTAssertEqual(page.messages.map(\.id), ["a", "b"])
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 20)
    }

    func test_givenEmptyTimeline_whenLoading_thenReturnsEmptyPageWithoutMore() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: [], total: 0, hasMore: false))
        let service = MessagesService(api: api)

        // When
        let page = try await service.timeline(scope: .all, tag: nil, limit: 20, offset: 0)

        // Then
        XCTAssertTrue(page.messages.isEmpty)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    // MARK: - Timeline: API failure

    func test_givenAPIFailureAndNoStore_whenLoadingTimeline_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "nope"))
        let service = MessagesService(api: api)

        // When / Then
        do {
            _ = try await service.timeline(scope: .all, tag: nil, limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "nope"))
        }
    }

    // MARK: - Stale-while-revalidate (with store)

    func test_givenStore_whenTimelineSucceeds_thenWritesPageThrough() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["a", "b"]))
        let store = InMemoryMessageStore()
        let service = MessagesService(api: api, store: store)

        // When
        _ = try await service.timeline(scope: .mine, tag: "swift", limit: 20, offset: 0)

        // Then
        let cached = await store.cachedTimeline(scope: .mine, tag: "swift")
        XCTAssertEqual(cached.map(\.id), ["a", "b"])
    }

    func test_givenStoreWithCacheAndAPIFailure_whenTimeline_thenReturnsCachedPage() async throws {
        // Given a primed cache and a failing API
        let store = InMemoryMessageStore()
        await store.replaceTimeline(
            [Message(from: sampleDTO(id: "cached"))],
            scope: .all,
            tag: nil
        )
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = MessagesService(api: api, store: store)

        // When
        let page = try await service.timeline(scope: .all, tag: nil, limit: 20, offset: 0)

        // Then — the stale cache is surfaced instead of throwing.
        XCTAssertEqual(page.messages.map(\.id), ["cached"])
        XCTAssertFalse(page.hasMore)
    }

    func test_givenStoreWithEmptyCacheAndAPIFailure_whenTimeline_thenThrows() async throws {
        // Given an empty cache and a failing API
        let store = InMemoryMessageStore()
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: nil))
        let service = MessagesService(api: api, store: store)

        // When / Then — nothing to fall back to, so the error surfaces.
        do {
            _ = try await service.timeline(scope: .all, tag: nil, limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: nil))
        }
    }

    // MARK: - Timeline stream

    func test_givenStoreWithCache_whenStreaming_thenYieldsCachedThenFresh() async throws {
        // Given a primed cache and a successful refresh
        let store = InMemoryMessageStore()
        await store.replaceTimeline([Message(from: sampleDTO(id: "old"))], scope: .all, tag: nil)
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["new"]))
        let service = MessagesService(api: api, store: store)

        // When
        var pages: [[String]] = []
        for try await page in service.timelineStream(scope: .all, tag: nil, limit: 20, offset: 0) {
            pages.append(page.messages.map(\.id))
        }

        // Then — cached page first, then the refreshed page.
        XCTAssertEqual(pages, [["old"], ["new"]])
    }

    func test_givenNoStore_whenStreaming_thenYieldsOnlyFreshPage() async throws {
        // Given no store
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["new"]))
        let service = MessagesService(api: api)

        // When
        var pages: [[String]] = []
        for try await page in service.timelineStream(scope: .all, tag: nil, limit: 20, offset: 0) {
            pages.append(page.messages.map(\.id))
        }

        // Then — exactly one element: the live page.
        XCTAssertEqual(pages, [["new"]])
    }

    // MARK: - Detail

    func test_givenMessageID_whenLoadingDetail_thenMapsAndCaches() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m42"))
        let store = InMemoryMessageStore()
        let service = MessagesService(api: api, store: store)

        // When
        let message = try await service.message(id: "m42")

        // Then
        XCTAssertEqual(message.id, "m42")
        let cached = await store.cachedMessage(id: "m42")
        XCTAssertEqual(cached?.id, "m42")
    }

    func test_givenDetailFailureWithCachedCopy_whenLoading_thenReturnsCached() async throws {
        // Given a cached message and a failing detail fetch
        let store = InMemoryMessageStore()
        await store.upsert([Message(from: sampleDTO(id: "m42"))])
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = MessagesService(api: api, store: store)

        // When
        let message = try await service.message(id: "m42")

        // Then
        XCTAssertEqual(message.id, "m42")
    }

    func test_givenDetailNotFoundAndNoCache_whenLoading_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "gone"))
        let service = MessagesService(api: api, store: InMemoryMessageStore())

        // When / Then
        do {
            _ = try await service.message(id: "missing")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "gone"))
        }
    }

    // MARK: - Replies

    func test_givenReplies_whenLoading_thenMapsAllReplies() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.repliesEnvelope(ids: ["r1", "r2"]))
        let service = MessagesService(api: api)

        // When
        let replies = try await service.replies(of: "m1", limit: 20, offset: 0)

        // Then
        XCTAssertEqual(replies.map(\.id), ["r1", "r2"])
    }

    func test_givenNoReplies_whenLoading_thenReturnsEmptyArray() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.repliesEnvelope(ids: []))
        let service = MessagesService(api: api)

        // When
        let replies = try await service.replies(of: "m1", limit: 20, offset: 0)

        // Then
        XCTAssertTrue(replies.isEmpty)
    }

    func test_givenRepliesAPIFailure_whenLoading_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "bad id"))
        let service = MessagesService(api: api)

        // When / Then
        do {
            _ = try await service.replies(of: "", limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "bad id"))
        }
    }

    // MARK: - Helpers

    private func sampleDTO(id: String) -> MessageDTO {
        MessageDTO(
            id: id,
            content: "hi",
            publiclyVisible: true,
            userId: "u1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            digCount: 0,
            pushCount: 0,
            user: UserSummaryDTO(id: "u1", username: "ada"),
            dugByMe: false
        )
    }
}
