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

    // MARK: - M2 write surface: create

    func test_givenBody_whenCreating_thenPostsToMessagesAndReturnsDomainMessage() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-new", content: "hello"))
        let store = InMemoryMessageStore()
        let service = MessagesService(api: api, store: store)

        // When
        let message = try await service.create(
            body: "hello",
            parentId: nil,
            tags: ["swift"],
            visibility: .public,
            pushedMessageId: nil
        )

        // Then
        XCTAssertEqual(message.id, "m-new")
        XCTAssertEqual(message.text, "hello")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/messages")
        let cached = await store.cachedMessage(id: "m-new")
        XCTAssertEqual(cached?.id, "m-new")
    }

    func test_givenEmptyBody_whenCreating_thenStillPostsAndReturnsServerResponse() async throws {
        // Given — boundary: the API permits an empty content (bare reposts use
        // this shape). The domain layer does not pre-validate; it forwards
        // whatever the caller supplied and trusts the server to reject as
        // needed.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-empty", content: ""))
        let service = MessagesService(api: api)

        // When
        let message = try await service.create(
            body: "",
            parentId: nil,
            tags: [],
            visibility: .public,
            pushedMessageId: nil
        )

        // Then
        XCTAssertEqual(message.id, "m-empty")
        XCTAssertEqual(message.text, "")
    }

    func test_givenAPIFailure_whenCreating_thenThrows() async throws {
        // Given — invalid input: server rejects with 400.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "content too long"))
        let service = MessagesService(api: api)

        // When / Then
        do {
            _ = try await service.create(
                body: String(repeating: "x", count: 5_000),
                parentId: nil,
                tags: [],
                visibility: .public,
                pushedMessageId: nil
            )
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "content too long"))
        }
    }

    func test_givenPrivateVisibility_whenCreating_thenStoresPrivateVisibility() async throws {
        // Given — happy path covering visibility round-trip.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-priv", publiclyVisible: false))
        let service = MessagesService(api: api)

        // When
        let message = try await service.create(
            body: "secret",
            parentId: nil,
            tags: [],
            visibility: .private,
            pushedMessageId: nil
        )

        // Then
        XCTAssertEqual(message.visibility, .private)
    }

    // MARK: - M2 write surface: reply

    func test_givenParent_whenReplying_thenForwardsParentIdToCreate() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "r-1", parentId: "m-parent"))
        let service = MessagesService(api: api)

        // When
        let reply = try await service.reply(
            to: "m-parent",
            body: "great post",
            tags: [],
            visibility: .public
        )

        // Then
        XCTAssertEqual(reply.parentID, "m-parent")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/messages")
        XCTAssertEqual(recorded.first?.method, "POST")
    }

    func test_givenEmptyParentId_whenReplying_thenStillForwardsToCreate() async throws {
        // Given — invalid input case: empty parent. The domain layer doesn't
        // pre-validate; it forwards to `create` and lets the server reject.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "missing parent"))
        let service = MessagesService(api: api)

        // When / Then
        do {
            _ = try await service.reply(to: "", body: "hi", tags: [], visibility: .public)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "missing parent"))
        }
    }

    // MARK: - M2 write surface: repost

    func test_givenOriginal_whenReposting_thenSendsPushedMessageId() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "rp-1", pushedMessageId: "m-orig"))
        let service = MessagesService(api: api)

        // When
        let repost = try await service.repost(
            "m-orig",
            commentary: "this!",
            visibility: .public
        )

        // Then
        XCTAssertEqual(repost.id, "rp-1")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/messages")
    }

    func test_givenNoCommentary_whenReposting_thenSendsEmptyBodyAndStillReturnsMessage() async throws {
        // Given — boundary: a bare repost with no commentary.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "rp-2", content: ""))
        let service = MessagesService(api: api)

        // When
        let repost = try await service.repost("m-orig", commentary: nil, visibility: .public)

        // Then
        XCTAssertEqual(repost.text, "")
    }

    func test_givenRepostAPIFailure_whenReposting_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "blocked author"))
        let service = MessagesService(api: api)

        // When / Then
        do {
            _ = try await service.repost("m-orig", commentary: nil, visibility: .public)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "blocked author"))
        }
    }

    // MARK: - M2 write surface: update (edit)

    func test_givenEdits_whenUpdating_thenPutsToMessageIdAndCachesResult() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-42", content: "edited"))
        let store = InMemoryMessageStore()
        let service = MessagesService(api: api, store: store)

        // When
        let updated = try await service.update(
            messageId: "m-42",
            body: "edited",
            tags: ["swift"],
            visibility: .public
        )

        // Then
        XCTAssertEqual(updated.text, "edited")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/messages/m-42")
        let cached = await store.cachedMessage(id: "m-42")
        XCTAssertEqual(cached?.text, "edited")
    }

    func test_givenEmptyBody_whenUpdating_thenStillIssuesPut() async throws {
        // Given — boundary: empty body. Forwarded as-is; server validates.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-42", content: ""))
        let service = MessagesService(api: api)

        // When
        let updated = try await service.update(
            messageId: "m-42",
            body: "",
            tags: [],
            visibility: .public
        )

        // Then
        XCTAssertEqual(updated.text, "")
    }

    func test_givenUpdateAPIFailure_whenUpdating_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "gone"))
        let service = MessagesService(api: api)

        // When / Then
        do {
            _ = try await service.update(
                messageId: "missing",
                body: "x",
                tags: [],
                visibility: .public
            )
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "gone"))
        }
    }

    // MARK: - M2 write surface: delete

    func test_givenMessageId_whenDeleting_thenIssuesDeleteAndRemovesFromCache() async throws {
        // Given a primed cache that holds the message.
        let store = InMemoryMessageStore()
        await store.upsert([Message(from: sampleDTO(id: "m-del"))])
        let api = StubAPIClient()
        // `sendVoid` consumes one queued outcome but discards the bytes —
        // any non-failure entry works.
        await api.enqueue(json: "{}")
        let service = MessagesService(api: api, store: store)

        // When
        try await service.delete(messageId: "m-del")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/messages/m-del")
        let cached = await store.cachedMessage(id: "m-del")
        XCTAssertNil(cached, "Deleted message must be evicted from the by-id cache.")
    }

    func test_givenMessageNotCached_whenDeleting_thenStillSucceeds() async throws {
        // Given — boundary: deleting a message we never cached.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = MessagesService(api: api, store: InMemoryMessageStore())

        // When / Then — no throw.
        try await service.delete(messageId: "never-cached")
    }

    func test_givenDeleteAPIFailure_whenDeleting_thenThrowsAndLeavesCacheIntact() async throws {
        // Given a primed cache and a failing server delete.
        let store = InMemoryMessageStore()
        await store.upsert([Message(from: sampleDTO(id: "m-keep"))])
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "not yours"))
        let service = MessagesService(api: api, store: store)

        // When / Then
        do {
            try await service.delete(messageId: "m-keep")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "not yours"))
        }
        // Cache must remain untouched on a failed delete.
        let cached = await store.cachedMessage(id: "m-keep")
        XCTAssertNotNil(cached)
    }

    // MARK: - M2 write surface: dig / undig

    func test_givenMessage_whenDigging_thenReturnsMessageWithUpdatedDigCount() async throws {
        // Given — dig endpoint, followed by the get-by-id refresh the service
        // issues to fold the new count into a full `Message`.
        let api = StubAPIClient()
        await api.enqueue(json: """
        { "digCount": 5, "dugByMe": true, "isNewDig": true }
        """)
        await api.enqueue(json: Fixtures.messageObject(id: "m-dig", digCount: 4, dugByMe: false))
        let store = InMemoryMessageStore()
        let service = MessagesService(api: api, store: store)

        // When
        let updated = try await service.dig(messageId: "m-dig")

        // Then — the dig response's count/flag win over the get-by-id payload.
        XCTAssertEqual(updated.id, "m-dig")
        XCTAssertEqual(updated.digCount, 5)
        XCTAssertTrue(updated.didDig)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/messages/m-dig/dig")
        let cached = await store.cachedMessage(id: "m-dig")
        XCTAssertEqual(cached?.digCount, 5)
        XCTAssertEqual(cached?.didDig, true)
    }

    func test_givenAlreadyDug_whenUndigging_thenReturnsMessageWithDecrementedCount() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: """
        { "digCount": 3, "dugByMe": false }
        """)
        await api.enqueue(json: Fixtures.messageObject(id: "m-undig", digCount: 4, dugByMe: true))
        let service = MessagesService(api: api)

        // When
        let updated = try await service.undig(messageId: "m-undig")

        // Then
        XCTAssertEqual(updated.digCount, 3)
        XCTAssertFalse(updated.didDig)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/messages/m-undig/dig")
    }

    func test_givenDigAPIFailure_whenDigging_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "sign in"))
        let service = MessagesService(api: api)

        // When / Then
        do {
            _ = try await service.dig(messageId: "m-x")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "sign in"))
        }
    }

    func test_givenDigSucceedsButRefreshFails_whenDigging_thenThrows() async throws {
        // Given — boundary: dig POST succeeded, but the follow-up get-by-id
        // refresh failed. The service surfaces the failure so the caller
        // doesn't render a half-merged message.
        let api = StubAPIClient()
        await api.enqueue(json: """
        { "digCount": 9, "dugByMe": true, "isNewDig": true }
        """)
        await api.enqueue(failure: .transport(message: "offline"))
        let service = MessagesService(api: api)

        // When / Then
        do {
            _ = try await service.dig(messageId: "m-x")
            XCTFail("Expected an APIError from the refresh leg")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport(message: "offline"))
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
