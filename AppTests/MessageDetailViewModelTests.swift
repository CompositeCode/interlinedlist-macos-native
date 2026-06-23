// MessageDetailViewModelTests
//
// BDD-named tests for the M2 additions on `MessageDetailViewModel`:
// inline reply, optimistic dig on the root and on replies, root
// delete with `didDeleteRoot`, and composer-event consumption.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class MessageDetailViewModelTests: XCTestCase {

    // MARK: - postReply

    func test_givenValidBody_whenPostingReply_thenAppendsToRepliesArray() async throws {
        // Given
        let stub = StubMessagesService()
        let reply = MessageFixtures.message(id: "r-new", parentID: "m1")
        await stub.enqueueReply(success: reply)
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")

        // When
        let posted = await viewModel.postReply(body: "hello", visibility: .public)

        // Then
        XCTAssertEqual(posted?.id, "r-new")
        XCTAssertEqual(viewModel.replies.map(\.id), ["r-new"])
        XCTAssertNil(viewModel.replyError)
        let recorded = await stub.recorded
        if case .reply(let to, let body, _, _) = recorded.first?.kind {
            XCTAssertEqual(to, "m1")
            XCTAssertEqual(body, "hello")
        } else {
            XCTFail("Expected a `reply` call, got \(String(describing: recorded.first))")
        }
    }

    func test_givenEmptyBody_whenPostingReply_thenReturnsNilAndDoesNotCall() async {
        // Given — invalid input case.
        let stub = StubMessagesService()
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")

        // When
        let posted = await viewModel.postReply(body: "   ")

        // Then
        XCTAssertNil(posted)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenReplyAPIFailure_whenPostingReply_thenSurfacesReplyErrorAndDoesNotAppend() async {
        // Given — upstream API failure.
        let stub = StubMessagesService()
        let failure = TestError.upstream("oops")
        await stub.enqueueReply(failure: failure)
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")

        // When
        let posted = await viewModel.postReply(body: "hello")

        // Then
        XCTAssertNil(posted)
        XCTAssertEqual(viewModel.replyError as? TestError, failure)
        XCTAssertTrue(viewModel.replies.isEmpty)
    }

    func test_givenWhitespaceOnlyBody_whenPostingReply_thenReturnsNilWithoutCall() async {
        // Given — boundary: whitespace only.
        let stub = StubMessagesService()
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")

        // When
        let posted = await viewModel.postReply(body: "\n\t  ")

        // Then
        XCTAssertNil(posted)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - toggleDig on root + reply

    func test_givenRootMessage_whenTogglingDig_thenServerCopyReplacesOptimisticFlip() async {
        // Given
        let stub = StubMessagesService()
        let confirmed = MessageFixtures.message(id: "m1", digCount: 7, didDig: true)
        await stub.enqueueDig(success: confirmed)
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")
        await stub.enqueueMessage(success: MessageFixtures.message(id: "m1", digCount: 6, didDig: false))
        await stub.enqueueReplies(success: [])
        await viewModel.load()

        // When
        if let root = viewModel.message {
            await viewModel.toggleDig(on: root)
        } else {
            XCTFail("Expected a loaded root message")
        }

        // Then
        XCTAssertEqual(viewModel.message?.digCount, 7)
        XCTAssertEqual(viewModel.message?.didDig, true)
    }

    func test_givenReply_whenTogglingDig_thenReplyEntryIsUpdated() async {
        // Given
        let stub = StubMessagesService()
        let originalReply = MessageFixtures.message(id: "r1", digCount: 1, didDig: false, parentID: "m1")
        let confirmed = MessageFixtures.message(id: "r1", digCount: 2, didDig: true, parentID: "m1")
        await stub.enqueueDig(success: confirmed)
        await stub.enqueueMessage(success: MessageFixtures.message(id: "m1"))
        await stub.enqueueReplies(success: [originalReply])
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")
        await viewModel.load()

        // When
        await viewModel.toggleDig(on: originalReply)

        // Then
        XCTAssertEqual(viewModel.replies.first?.didDig, true)
        XCTAssertEqual(viewModel.replies.first?.digCount, 2)
    }

    func test_givenDigFailure_whenTogglingDigOnRoot_thenRollsBack() async {
        // Given — upstream API failure path for optimistic UI on the
        // detail screen.
        let stub = StubMessagesService()
        await stub.enqueueMessage(success: MessageFixtures.message(id: "m1", digCount: 3, didDig: false))
        await stub.enqueueReplies(success: [])
        let failure = TestError.upstream("forbidden")
        await stub.enqueueDig(failure: failure)
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")
        await viewModel.load()

        // When
        if let root = viewModel.message {
            await viewModel.toggleDig(on: root)
        }

        // Then — rolled back.
        XCTAssertEqual(viewModel.message?.digCount, 3)
        XCTAssertEqual(viewModel.message?.didDig, false)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - deleteCurrentMessage

    func test_givenRoot_whenDeletingCurrentMessage_thenSetsDidDeleteRoot() async {
        // Given
        let stub = StubMessagesService()
        await stub.enqueueDeleteSuccess()
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")

        // When
        await viewModel.deleteCurrentMessage()

        // Then
        XCTAssertTrue(viewModel.didDeleteRoot)
        XCTAssertNil(viewModel.error)
    }

    func test_givenDeleteFailure_whenDeletingCurrentMessage_thenSurfacesErrorAndKeepsRoot() async {
        // Given
        let stub = StubMessagesService()
        let failure = TestError.upstream("not yours")
        await stub.enqueueDelete(failure: failure)
        let viewModel = MessageDetailViewModel(messages: stub, messageID: "m1")

        // When
        await viewModel.deleteCurrentMessage()

        // Then
        XCTAssertFalse(viewModel.didDeleteRoot)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - apply(event:)

    func test_givenReplyCreatedEventForThisParent_whenApplied_thenAppendsReply() {
        // Given
        let viewModel = MessageDetailViewModel(messages: StubMessagesService(), messageID: "m1")
        let reply = MessageFixtures.message(id: "r-new", parentID: "m1")

        // When
        viewModel.apply(event: .replyCreated(parentID: "m1", reply: reply))

        // Then
        XCTAssertEqual(viewModel.replies.map(\.id), ["r-new"])
    }

    func test_givenReplyCreatedEventForOtherParent_whenApplied_thenIsNoop() {
        // Given — boundary: event targets another thread.
        let viewModel = MessageDetailViewModel(messages: StubMessagesService(), messageID: "m1")
        let unrelated = MessageFixtures.message(id: "r-other", parentID: "m99")

        // When
        viewModel.apply(event: .replyCreated(parentID: "m99", reply: unrelated))

        // Then
        XCTAssertTrue(viewModel.replies.isEmpty)
    }

    func test_givenMessageDeletedEventForRoot_whenApplied_thenSetsDidDeleteRoot() {
        // Given
        let viewModel = MessageDetailViewModel(messages: StubMessagesService(), messageID: "m1")

        // When
        viewModel.apply(event: .messageDeleted(id: "m1"))

        // Then
        XCTAssertTrue(viewModel.didDeleteRoot)
    }

    // MARK: - canEdit ownership gating

    func test_givenNilCurrentUserID_whenCheckingCanEdit_thenReturnsFalse() {
        let viewModel = MessageDetailViewModel(messages: StubMessagesService(), messageID: "m1")
        let m = MessageFixtures.message(id: "m1", author: MessageFixtures.author(id: "owner"))
        XCTAssertFalse(viewModel.canEdit(m, currentUserID: nil))
    }

    func test_givenMatchingAuthor_whenCheckingCanEdit_thenReturnsTrue() {
        let viewModel = MessageDetailViewModel(messages: StubMessagesService(), messageID: "m1")
        let m = MessageFixtures.message(id: "m1", author: MessageFixtures.author(id: "owner"))
        XCTAssertTrue(viewModel.canEdit(m, currentUserID: "owner"))
    }
}
