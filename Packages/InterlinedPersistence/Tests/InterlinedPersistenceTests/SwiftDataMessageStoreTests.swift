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

    // MARK: - Scheduled slice

    func test_givenReplacedScheduled_whenReadingScheduled_thenReturnsMessagesInScheduleOrder() async throws {
        // Given — three scheduled posts enqueued out of schedule order.
        let store = try SwiftDataMessageStore.inMemory()
        let later = sampleMessage(id: "later", scheduledAt: Date(timeIntervalSince1970: 3_000))
        let soon = sampleMessage(id: "soon", scheduledAt: Date(timeIntervalSince1970: 1_000))
        let mid = sampleMessage(id: "mid", scheduledAt: Date(timeIntervalSince1970: 2_000))

        // When
        await store.replaceScheduled([later, soon, mid])

        // Then — sorted by scheduledAt ascending.
        let cached = await store.cachedScheduled()
        XCTAssertEqual(cached.map(\.id), ["soon", "mid", "later"])
    }

    func test_givenEmptyStore_whenReadingScheduled_thenReturnsEmpty() async throws {
        // Given — boundary: nothing scheduled.
        let store = try SwiftDataMessageStore.inMemory()

        // When
        let cached = await store.cachedScheduled()

        // Then
        XCTAssertTrue(cached.isEmpty)
    }

    func test_givenScheduledReplacedTwice_whenReadingScheduled_thenReturnsLatestSliceOnly() async throws {
        // Given
        let store = try SwiftDataMessageStore.inMemory()
        await store.replaceScheduled([
            sampleMessage(id: "old-1", scheduledAt: Date(timeIntervalSince1970: 1_000)),
            sampleMessage(id: "old-2", scheduledAt: Date(timeIntervalSince1970: 2_000))
        ])

        // When — page replace: removed scheduled posts disappear.
        await store.replaceScheduled([
            sampleMessage(id: "new-1", scheduledAt: Date(timeIntervalSince1970: 5_000))
        ])

        // Then
        let cached = await store.cachedScheduled()
        XCTAssertEqual(cached.map(\.id), ["new-1"])
    }

    func test_givenReplaceScheduled_whenReadingTimeline_thenTimelineSliceUntouched() async throws {
        // Given — a timeline cache is primed, then a scheduled slice is written.
        let store = try SwiftDataMessageStore.inMemory()
        await store.replaceTimeline(
            [sampleMessage(id: "t-1"), sampleMessage(id: "t-2")],
            scope: .all,
            tag: nil
        )

        // When — the scheduled slice replacement must NOT clobber the timeline.
        await store.replaceScheduled([
            sampleMessage(id: "s-1", scheduledAt: Date(timeIntervalSince1970: 9_000))
        ])

        // Then — the timeline slice still reads back intact.
        let timeline = await store.cachedTimeline(scope: .all, tag: nil)
        XCTAssertEqual(timeline.map(\.id), ["t-1", "t-2"])
        let scheduled = await store.cachedScheduled()
        XCTAssertEqual(scheduled.map(\.id), ["s-1"])
    }

    func test_givenEmptyScheduledSlice_whenReplacing_thenClearsPriorScheduledButKeepsTimeline() async throws {
        // Given — boundary: a prior scheduled slice plus a timeline cache.
        let store = try SwiftDataMessageStore.inMemory()
        await store.replaceTimeline([sampleMessage(id: "t-1")], scope: .all, tag: nil)
        await store.replaceScheduled([
            sampleMessage(id: "s-1", scheduledAt: Date(timeIntervalSince1970: 1_000))
        ])

        // When — replacing with an empty slice clears the scheduled cache only.
        await store.replaceScheduled([])

        // Then
        let scheduled = await store.cachedScheduled()
        let timeline = await store.cachedTimeline(scope: .all, tag: nil)
        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertEqual(timeline.map(\.id), ["t-1"])
    }

    func test_givenScheduledSlice_whenReadingTimeline_thenScheduledNotSurfacedAsTimeline() async throws {
        // Given — only a scheduled slice, no timeline page written.
        let store = try SwiftDataMessageStore.inMemory()
        await store.replaceScheduled([
            sampleMessage(id: "s-1", scheduledAt: Date(timeIntervalSince1970: 1_000))
        ])

        // When
        let timeline = await store.cachedTimeline(scope: .all, tag: nil)

        // Then — a scheduled post is never served as a published timeline entry.
        XCTAssertTrue(timeline.isEmpty)
    }

    // MARK: - Scheduled slice — on-disk round-trip

    func test_givenScheduledCachedOnDisk_whenReopeningStore_thenSurvivesRelaunch() async throws {
        // Given — write a scheduled slice through an on-disk store, then drop
        // the actor and reopen the same file (simulates an app relaunch).
        let url = Self.makeTempStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        let scheduledAt = Date(timeIntervalSince1970: 1_800_000_000)
        do {
            let store = try SwiftDataMessageStore.onDisk(at: url)
            await store.replaceScheduled([
                sampleMessage(id: "s-1", text: "future post", scheduledAt: scheduledAt)
            ])
        }

        // When — a fresh store instance opens the same file.
        let reopened = try SwiftDataMessageStore.onDisk(at: url)
        let cached = await reopened.cachedScheduled()

        // Then — the scheduled slice survived the relaunch.
        XCTAssertEqual(cached.map(\.id), ["s-1"])
        XCTAssertEqual(cached.first?.text, "future post")
        XCTAssertEqual(cached.first?.scheduledAt, scheduledAt)
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

    /// A unique temp URL for an on-disk SwiftData store file.
    private static func makeTempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageStoreTest-\(UUID().uuidString).store")
    }

    /// Removes a SQLite store file and its `-shm` / `-wal` siblings.
    private static func removeStoreFiles(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

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
