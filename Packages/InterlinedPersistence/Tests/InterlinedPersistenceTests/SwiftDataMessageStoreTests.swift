import XCTest
import InterlinedDomain
@testable import InterlinedPersistence

final class SwiftDataMessageStoreTests: XCTestCase {

    // MARK: - Timeline cache

    func test_givenReplacedTimeline_whenReadingSameKey_thenReturnsMessagesInOrder() async throws {
        // Given
        let store = try SwiftDataMessageStore.inMemory()
        let messages = [
            sampleMessage(id: "a", text: "first"),
            sampleMessage(id: "b", text: "second"),
            sampleMessage(id: "c", text: "third")
        ]

        // When
        await store.replaceTimeline(messages, scope: .all, tag: nil)

        // Then
        let cached = await store.cachedTimeline(scope: .all, tag: nil)
        XCTAssertEqual(cached.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(cached.map(\.text), ["first", "second", "third"])
    }

    func test_givenTwoDistinctTimelineKeys_whenReadingEach_thenIsolatedFromEachOther() async throws {
        // Given
        let store = try SwiftDataMessageStore.inMemory()

        // When
        await store.replaceTimeline(
            [sampleMessage(id: "a")],
            scope: .all,
            tag: nil
        )
        await store.replaceTimeline(
            [sampleMessage(id: "b")],
            scope: .mine,
            tag: "swift"
        )

        // Then — each key returns its own slice, no cross-pollination.
        let all = await store.cachedTimeline(scope: .all, tag: nil)
        let mineSwift = await store.cachedTimeline(scope: .mine, tag: "swift")
        let mineNoTag = await store.cachedTimeline(scope: .mine, tag: nil)
        let allSwift = await store.cachedTimeline(scope: .all, tag: "swift")

        XCTAssertEqual(all.map(\.id), ["a"])
        XCTAssertEqual(mineSwift.map(\.id), ["b"])
        XCTAssertTrue(mineNoTag.isEmpty)
        XCTAssertTrue(allSwift.isEmpty)
    }

    func test_givenReplacedTimelineThenReplacedAgain_whenReadingKey_thenReturnsLatestOnly() async throws {
        // Given — first page lands, then a fresh page replaces it.
        let store = try SwiftDataMessageStore.inMemory()
        await store.replaceTimeline(
            [sampleMessage(id: "a"), sampleMessage(id: "b")],
            scope: .all,
            tag: nil
        )

        // When
        await store.replaceTimeline(
            [sampleMessage(id: "c")],
            scope: .all,
            tag: nil
        )

        // Then — the second replace fully supersedes the first.
        let cached = await store.cachedTimeline(scope: .all, tag: nil)
        XCTAssertEqual(cached.map(\.id), ["c"])
    }

    func test_givenEmptyStore_whenReadingTimeline_thenReturnsEmpty() async throws {
        // Given
        let store = try SwiftDataMessageStore.inMemory()

        // When
        let cached = await store.cachedTimeline(scope: .all, tag: nil)

        // Then
        XCTAssertTrue(cached.isEmpty)
    }

    // MARK: - By-id upsert

    func test_givenUpsertedMessage_whenReadingByID_thenRoundTripsAllFields() async throws {
        // Given
        let store = try SwiftDataMessageStore.inMemory()
        let original = sampleMessage(
            id: "x",
            text: "round-trip me",
            tags: ["swift", "macos"],
            visibility: .private,
            parentID: "parent-1",
            scheduledAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        // When
        await store.upsert([original])

        // Then
        let fetched = await store.cachedMessage(id: "x")
        XCTAssertEqual(fetched, original)
    }

    func test_givenUpsertedTwice_whenReadingByID_thenSecondWriteWins() async throws {
        // Given
        let store = try SwiftDataMessageStore.inMemory()

        // When
        await store.upsert([sampleMessage(id: "a", text: "v1")])
        await store.upsert([sampleMessage(id: "a", text: "v2")])

        // Then — update semantics, not duplicate.
        let fetched = await store.cachedMessage(id: "a")
        XCTAssertEqual(fetched?.text, "v2")
    }

    func test_givenEmptyStore_whenReadingMessageByID_thenReturnsNil() async throws {
        // Given
        let store = try SwiftDataMessageStore.inMemory()

        // When
        let fetched = await store.cachedMessage(id: "nope")

        // Then
        XCTAssertNil(fetched)
    }

    func test_givenReplacedTimeline_whenReadingMessageByID_thenAlsoIndexed() async throws {
        // Given — matches InMemoryMessageStore semantics: replaceTimeline
        // also populates the by-id index.
        let store = try SwiftDataMessageStore.inMemory()

        // When
        await store.replaceTimeline([sampleMessage(id: "a")], scope: .all, tag: nil)

        // Then
        let byID = await store.cachedMessage(id: "a")
        XCTAssertEqual(byID?.id, "a")
    }

    // MARK: - Clear

    func test_givenPopulatedStore_whenCleared_thenTimelineAndByIDCachesBothEmpty() async throws {
        // Given
        let store = try SwiftDataMessageStore.inMemory()
        await store.replaceTimeline(
            [sampleMessage(id: "a"), sampleMessage(id: "b")],
            scope: .all,
            tag: nil
        )
        await store.upsert([sampleMessage(id: "c")])

        // When
        await store.clear()

        // Then — both indexes are empty.
        let timeline = await store.cachedTimeline(scope: .all, tag: nil)
        let a = await store.cachedMessage(id: "a")
        let b = await store.cachedMessage(id: "b")
        let c = await store.cachedMessage(id: "c")
        XCTAssertTrue(timeline.isEmpty)
        XCTAssertNil(a)
        XCTAssertNil(b)
        XCTAssertNil(c)
    }

    // MARK: - Repost re-hydration

    func test_givenRepostedMessageInCache_whenReadingReposter_thenRepostHydrated() async throws {
        // Given — the original is cached, and the reposter references it.
        let store = try SwiftDataMessageStore.inMemory()
        let original = sampleMessage(id: "orig", text: "the original")
        let reposter = sampleMessage(
            id: "repost",
            text: "look at this",
            repost: .message(original)
        )

        // When
        await store.upsert([original, reposter])

        // Then — the repost target re-hydrates from the by-id cache.
        let fetched = await store.cachedMessage(id: "repost")
        XCTAssertEqual(fetched?.repost?.original.id, "orig")
        XCTAssertEqual(fetched?.repost?.original.text, "the original")
    }

    func test_givenRepostedMessageMissingFromCache_whenReadingReposter_thenRepostDroppedSilently() async throws {
        // Given — only the reposter is cached; the original is not. The
        // store treats the cache as best-effort, so the repost reference
        // should silently drop rather than throw.
        let store = try SwiftDataMessageStore.inMemory()
        let original = sampleMessage(id: "ghost", text: "not cached")
        let reposter = sampleMessage(
            id: "repost",
            text: "look at this",
            repost: .message(original)
        )

        // When
        await store.upsert([reposter])

        // Then
        let fetched = await store.cachedMessage(id: "repost")
        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched?.repost)
    }

    // MARK: - Concurrency sanity

    func test_givenConcurrentUpsertsOfDifferentIDs_whenAllComplete_thenAllReadable() async throws {
        // Given — actor isolation should serialize SwiftData mutations,
        // even when two Tasks fire upserts at the same time. Build the
        // Sendable payloads up front so `async let` only crosses the
        // isolation boundary with `Message` values, not `self`.
        let store = try SwiftDataMessageStore.inMemory()
        let first = sampleMessage(id: "task-1", text: "one")
        let second = sampleMessage(id: "task-2", text: "two")

        // When
        async let one: Void = store.upsert([first])
        async let two: Void = store.upsert([second])
        _ = await (one, two)

        // Then — both writes survived, neither crashed the actor.
        let firstFetched = await store.cachedMessage(id: "task-1")
        let secondFetched = await store.cachedMessage(id: "task-2")
        XCTAssertEqual(firstFetched?.text, "one")
        XCTAssertEqual(secondFetched?.text, "two")
    }

    // MARK: - Helpers

    private func sampleMessage(
        id: String,
        text: String = "hi",
        tags: [String] = [],
        visibility: Visibility = .public,
        parentID: String? = nil,
        repost: Repost? = nil,
        scheduledAt: Date? = nil
    ) -> Message {
        Message(
            id: id,
            author: UserSummary(
                id: "u1",
                username: "ada",
                displayName: "Ada",
                avatarURL: URL(string: "https://example.test/ada.png")
            ),
            text: text,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: tags,
            visibility: visibility,
            digCount: 0,
            didDig: false,
            repostCount: 0,
            replyCount: nil,
            parentID: parentID,
            repost: repost,
            scheduledAt: scheduledAt
        )
    }
}
