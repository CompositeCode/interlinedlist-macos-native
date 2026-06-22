import XCTest
@testable import InterlinedDomain

final class InMemoryMessageStoreTests: XCTestCase {

    func test_givenEmptyStore_whenReadingTimeline_thenReturnsEmpty() async {
        // Given
        let store = InMemoryMessageStore()

        // When
        let messages = await store.cachedTimeline(scope: .all, tag: nil)

        // Then
        XCTAssertTrue(messages.isEmpty)
    }

    func test_givenReplacedTimeline_whenReadingSameKey_thenReturnsMessages() async {
        // Given
        let store = InMemoryMessageStore()
        let message = sampleMessage(id: "a")

        // When
        await store.replaceTimeline([message], scope: .mine, tag: "swift")

        // Then
        let same = await store.cachedTimeline(scope: .mine, tag: "swift")
        XCTAssertEqual(same.map(\.id), ["a"])
        // And a different key is unaffected.
        let other = await store.cachedTimeline(scope: .all, tag: nil)
        XCTAssertTrue(other.isEmpty)
    }

    func test_givenReplacedTimeline_whenReadingMessageByID_thenAlsoIndexed() async {
        // Given
        let store = InMemoryMessageStore()

        // When
        await store.replaceTimeline([sampleMessage(id: "a")], scope: .all, tag: nil)

        // Then — replaceTimeline also populates the by-id index.
        let byID = await store.cachedMessage(id: "a")
        XCTAssertEqual(byID?.id, "a")
    }

    func test_givenUpsertedMessage_whenRead_thenReturnsLatest() async {
        // Given
        let store = InMemoryMessageStore()

        // When
        await store.upsert([sampleMessage(id: "a", text: "v1")])
        await store.upsert([sampleMessage(id: "a", text: "v2")])

        // Then
        let message = await store.cachedMessage(id: "a")
        XCTAssertEqual(message?.text, "v2")
    }

    func test_givenCachedMessage_whenRemoved_thenGoneFromByIdAndTimeline() async {
        // Given a message that exists in both the by-id and the timeline
        // index.
        let store = InMemoryMessageStore()
        await store.replaceTimeline(
            [sampleMessage(id: "a"), sampleMessage(id: "b")],
            scope: .all,
            tag: nil
        )

        // When
        await store.remove(id: "a")

        // Then
        let removed = await store.cachedMessage(id: "a")
        XCTAssertNil(removed)
        let timeline = await store.cachedTimeline(scope: .all, tag: nil)
        XCTAssertEqual(timeline.map(\.id), ["b"])
    }

    func test_givenMissingId_whenRemoved_thenNoOp() async {
        // Given — boundary: removing an id that was never cached.
        let store = InMemoryMessageStore()
        await store.upsert([sampleMessage(id: "a")])

        // When
        await store.remove(id: "ghost")

        // Then — the existing message stays.
        let kept = await store.cachedMessage(id: "a")
        XCTAssertEqual(kept?.id, "a")
    }

    func test_givenPopulatedStore_whenCleared_thenEverythingGone() async {
        // Given
        let store = InMemoryMessageStore()
        await store.replaceTimeline([sampleMessage(id: "a")], scope: .all, tag: nil)

        // When
        await store.clear()

        // Then
        let timeline = await store.cachedTimeline(scope: .all, tag: nil)
        let message = await store.cachedMessage(id: "a")
        XCTAssertTrue(timeline.isEmpty)
        XCTAssertNil(message)
    }

    // MARK: - Helpers

    private func sampleMessage(id: String, text: String = "hi") -> Message {
        Message(
            id: id,
            author: UserSummary(id: "u1", username: "ada", displayName: "Ada"),
            text: text,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            visibility: .public,
            digCount: 0,
            didDig: false,
            repostCount: 0
        )
    }
}
