// TimelineViewModelTests
//
// BDD-named tests for the M2 additions on `TimelineViewModel`:
// optimistic dig + rollback, delete, composer-event consumption, and
// the ownership-gating helper. Read-paths from M1 are already covered
// in `InterlinedDomainTests.MessagesServiceTests` — these tests pin
// the view-model logic that lives in the App target.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class TimelineViewModelTests: XCTestCase {

    // MARK: - toggleDig optimistic UI

    func test_givenUndugMessage_whenTogglingDig_thenOptimisticFlipThenServerConfirmation() async {
        // Given — message present in the loaded list, not yet dug.
        let original = MessageFixtures.message(id: "m1", digCount: 3, didDig: false)
        let stub = StubMessagesService()
        let confirmed = MessageFixtures.message(id: "m1", digCount: 5, didDig: true) // server may report higher.
        await stub.enqueueDig(success: confirmed)
        let viewModel = TimelineViewModel(messages: stub)
        viewModel.seedForTest(messages: [original])

        // When
        await viewModel.toggleDig(on: original)

        // Then — final state replaces optimistic copy with server copy.
        XCTAssertEqual(viewModel.messagesLoaded.first?.digCount, 5)
        XCTAssertEqual(viewModel.messagesLoaded.first?.didDig, true)
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        if case .dig(let id) = recorded.first?.kind {
            XCTAssertEqual(id, "m1")
        } else {
            XCTFail("Expected a `dig` call, got \(String(describing: recorded.first))")
        }
    }

    func test_givenDigFailure_whenTogglingDig_thenRollsBackOptimisticFlip() async {
        // Given — upstream API failure case for optimistic UI.
        let original = MessageFixtures.message(id: "m1", digCount: 3, didDig: false)
        let stub = StubMessagesService()
        let failure = TestError.upstream("forbidden")
        await stub.enqueueDig(failure: failure)
        let viewModel = TimelineViewModel(messages: stub)
        viewModel.seedForTest(messages: [original])

        // When
        await viewModel.toggleDig(on: original)

        // Then — rolled back to pre-flip state and error surfaced.
        XCTAssertEqual(viewModel.messagesLoaded.first?.digCount, 3)
        XCTAssertEqual(viewModel.messagesLoaded.first?.didDig, false)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    func test_givenAlreadyDug_whenTogglingDig_thenCallsUndig() async {
        // Given
        let original = MessageFixtures.message(id: "m1", digCount: 4, didDig: true)
        let stub = StubMessagesService()
        let confirmed = MessageFixtures.message(id: "m1", digCount: 3, didDig: false)
        await stub.enqueueUndig(success: confirmed)
        let viewModel = TimelineViewModel(messages: stub)
        viewModel.seedForTest(messages: [original])

        // When
        await viewModel.toggleDig(on: original)

        // Then
        XCTAssertEqual(viewModel.messagesLoaded.first?.didDig, false)
        XCTAssertEqual(viewModel.messagesLoaded.first?.digCount, 3)
        let recorded = await stub.recorded
        if case .undig(let id) = recorded.first?.kind {
            XCTAssertEqual(id, "m1")
        } else {
            XCTFail("Expected an `undig` call, got \(String(describing: recorded.first))")
        }
    }

    func test_givenMessageNotInList_whenTogglingDig_thenIsNoop() async {
        // Given — boundary: the message is no longer in the rendered
        // list (deleted, scope changed, etc.). The view model bails.
        let detached = MessageFixtures.message(id: "ghost", digCount: 1, didDig: false)
        let stub = StubMessagesService()
        let viewModel = TimelineViewModel(messages: stub)
        viewModel.seedForTest(messages: [])

        // When
        await viewModel.toggleDig(on: detached)

        // Then — no call recorded.
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - deleteMessage

    func test_givenOwnMessage_whenDeleting_thenRemovesFromListAndCallsDelete() async {
        // Given
        let mine = MessageFixtures.message(id: "m1")
        let other = MessageFixtures.message(id: "m2")
        let stub = StubMessagesService()
        await stub.enqueueDeleteSuccess()
        let viewModel = TimelineViewModel(messages: stub)
        viewModel.seedForTest(messages: [mine, other])

        // When
        await viewModel.deleteMessage(id: "m1")

        // Then
        XCTAssertEqual(viewModel.messagesLoaded.map(\.id), ["m2"])
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        if case .delete(let id) = recorded.first?.kind {
            XCTAssertEqual(id, "m1")
        } else {
            XCTFail("Expected a `delete` call, got \(String(describing: recorded.first))")
        }
    }

    func test_givenDeleteFailure_whenDeleting_thenLeavesListIntactAndSurfacesError() async {
        // Given
        let mine = MessageFixtures.message(id: "m1")
        let stub = StubMessagesService()
        let failure = TestError.upstream("server down")
        await stub.enqueueDelete(failure: failure)
        let viewModel = TimelineViewModel(messages: stub)
        viewModel.seedForTest(messages: [mine])

        // When
        await viewModel.deleteMessage(id: "m1")

        // Then
        XCTAssertEqual(viewModel.messagesLoaded.map(\.id), ["m1"])
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - apply(event:)

    func test_givenMessageCreatedEvent_whenApplied_thenPrependsToList() {
        // Given
        let existing = MessageFixtures.message(id: "m1")
        let viewModel = TimelineViewModel(messages: StubMessagesService())
        viewModel.seedForTest(messages: [existing])
        let new = MessageFixtures.message(id: "m-new", text: "fresh")

        // When
        viewModel.apply(event: .messageCreated(new))

        // Then
        XCTAssertEqual(viewModel.messagesLoaded.map(\.id), ["m-new", "m1"])
    }

    func test_givenMessageDeletedEvent_whenApplied_thenRemovesFromList() {
        // Given
        let a = MessageFixtures.message(id: "a")
        let b = MessageFixtures.message(id: "b")
        let viewModel = TimelineViewModel(messages: StubMessagesService())
        viewModel.seedForTest(messages: [a, b])

        // When
        viewModel.apply(event: .messageDeleted(id: "a"))

        // Then
        XCTAssertEqual(viewModel.messagesLoaded.map(\.id), ["b"])
    }

    func test_givenMessageUpdatedEvent_whenApplied_thenReplacesInPlace() {
        // Given
        let a = MessageFixtures.message(id: "a", text: "old")
        let viewModel = TimelineViewModel(messages: StubMessagesService())
        viewModel.seedForTest(messages: [a])

        // When
        viewModel.apply(event: .messageUpdated(MessageFixtures.message(id: "a", text: "new")))

        // Then
        XCTAssertEqual(viewModel.messagesLoaded.first?.text, "new")
    }

    func test_givenReplyCreatedEvent_whenApplied_thenIsNoopForTimeline() {
        // Given — boundary: reply events belong to the detail view.
        let a = MessageFixtures.message(id: "a")
        let viewModel = TimelineViewModel(messages: StubMessagesService())
        viewModel.seedForTest(messages: [a])

        // When
        viewModel.apply(event: .replyCreated(
            parentID: "a",
            reply: MessageFixtures.message(id: "r1", text: "yo")
        ))

        // Then — timeline unchanged.
        XCTAssertEqual(viewModel.messagesLoaded.map(\.id), ["a"])
    }

    // MARK: - canEdit ownership gating

    func test_givenNilCurrentUserID_whenCheckingCanEdit_thenReturnsFalse() {
        // Given — session not yet resolved.
        let message = MessageFixtures.message(id: "m1", author: MessageFixtures.author(id: "owner"))
        let viewModel = TimelineViewModel(messages: StubMessagesService())

        // When / Then — hide affordance per the M2 rule.
        XCTAssertFalse(viewModel.canEdit(message, currentUserID: nil))
    }

    func test_givenAuthorMatchesCurrentUser_whenCheckingCanEdit_thenReturnsTrue() {
        let owner = MessageFixtures.author(id: "owner")
        let message = MessageFixtures.message(id: "m1", author: owner)
        let viewModel = TimelineViewModel(messages: StubMessagesService())

        XCTAssertTrue(viewModel.canEdit(message, currentUserID: "owner"))
    }

    func test_givenAuthorDiffersFromCurrentUser_whenCheckingCanEdit_thenReturnsFalse() {
        let message = MessageFixtures.message(id: "m1", author: MessageFixtures.author(id: "someone-else"))
        let viewModel = TimelineViewModel(messages: StubMessagesService())

        XCTAssertFalse(viewModel.canEdit(message, currentUserID: "me"))
    }
}

// MARK: - Test seam

// The view model intentionally has no public mutator for the loaded
// list (so production callers always go through the load methods).
// This `@testable`-friendly extension lets tests seed state directly
// for the M2 dig / delete / event tests, which would otherwise have
// to thread a full timeline load through a stub for every case.
extension TimelineViewModel {
    func seedForTest(messages: [Message]) {
        // Replays the same path the real loader uses to settle state,
        // via a one-element TimelinePage with no further pages.
        let page = TimelinePage(messages: messages, hasMore: false, nextOffset: nil)
        applyForTest(page)
    }

    /// Mirrors the private `apply(_:reset:)`. Kept inside the test
    /// target so the production type doesn't expose a setter.
    private func applyForTest(_ page: TimelinePage) {
        // Re-use the public `apply(event:)` plumbing to settle the
        // list by translating the page into a sequence of `.messageCreated`
        // prepends in reverse order so the final ordering matches the
        // page. This avoids needing any new private API on the view
        // model itself.
        // Reset the list to empty first; doing this by deleting any
        // currently-loaded messages would require knowing their ids.
        // Easier path: prepend in reverse so the result equals `page.messages`.
        for message in page.messages.reversed() {
            apply(event: .messageCreated(message))
        }
    }
}
