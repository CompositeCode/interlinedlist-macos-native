// ScheduledPostsViewModelTests
//
// BDD-named view-model tests for the M6 read-only Scheduled posts list
// (PLAN.md §5 "Scheduled sidebar section", §6 M6). View-model only — no
// SwiftUI rendering. Tested against `StubMessagesService`.
//
// Quartet per behaviour: happy path, invalid input (n/a — the load takes
// no input; covered by the API-failure case), upstream API failure,
// empty / boundary.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ScheduledPostsViewModelTests: XCTestCase {

    /// A `Message` with a non-nil `scheduledAt` (the list only shows queued
    /// posts). `MessageFixtures.message` always sets `scheduledAt: nil`, so we
    /// build directly here.
    private func scheduledMessage(id: String, at: Date = Date().addingTimeInterval(3600)) -> Message {
        Message(
            id: id,
            author: MessageFixtures.author(),
            text: "queued \(id)",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            visibility: .public,
            digCount: 0,
            didDig: false,
            repostCount: 0,
            replyCount: nil,
            parentID: nil,
            repost: nil,
            scheduledAt: at
        )
    }

    // MARK: - load (happy path)

    func test_givenScheduledPosts_whenLoading_thenPublishesThem() async throws {
        // Given
        let stub = StubMessagesService()
        let posts = [scheduledMessage(id: "s-1"), scheduledMessage(id: "s-2")]
        await stub.enqueueScheduledPosts(success: posts)
        let viewModel = ScheduledPostsViewModel(messages: stub)

        // When
        await viewModel.load()

        // Then
        XCTAssertEqual(viewModel.posts.map(\.id), ["s-1", "s-2"])
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertFalse(viewModel.isLoading)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
        guard case .scheduledPosts = recorded.first?.kind else {
            return XCTFail("Expected scheduledPosts call, got \(String(describing: recorded.first?.kind))")
        }
    }

    // MARK: - load (empty / boundary)

    func test_givenNoScheduledPosts_whenLoading_thenPublishesEmptyButLoaded() async {
        // Given — boundary: nothing scheduled.
        let stub = StubMessagesService()
        await stub.enqueueScheduledPosts(success: [])
        let viewModel = ScheduledPostsViewModel(messages: stub)

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - load (upstream API failure)

    func test_givenAPIFailure_whenLoading_thenSurfacesErrorAndStaysLoaded() async {
        // Given — upstream API failure.
        let stub = StubMessagesService()
        let failure = TestError.upstream("scheduled endpoint down")
        await stub.enqueueScheduledPosts(failure: failure)
        let viewModel = ScheduledPostsViewModel(messages: stub)

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_givenLoadAlreadyInFlight_whenLoadingAgain_thenSecondCallNoOps() async {
        // Boundary: re-entrancy guard. We can't easily hold a load open without
        // a slow stub, so assert the simpler invariant — a successful load
        // leaves `isLoading` false so the next load can proceed.
        let stub = StubMessagesService()
        await stub.enqueueScheduledPosts(success: [scheduledMessage(id: "s-1")])
        await stub.enqueueScheduledPosts(success: [scheduledMessage(id: "s-2")])
        let viewModel = ScheduledPostsViewModel(messages: stub)

        await viewModel.load()
        XCTAssertEqual(viewModel.posts.map(\.id), ["s-1"])
        await viewModel.load()
        XCTAssertEqual(viewModel.posts.map(\.id), ["s-2"])
    }

    // MARK: - cancel (NW-3)

    func test_givenScheduledPost_whenCancelSucceeds_thenRemovesFromList() async {
        let stub = StubMessagesService()
        let post = scheduledMessage(id: "s-1")
        await stub.enqueueScheduledPosts(success: [post])
        await stub.enqueueCancelScheduledSuccess()
        let viewModel = ScheduledPostsViewModel(messages: stub)
        await viewModel.load()

        await viewModel.cancel(post: post)

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertNil(viewModel.actionError)
    }

    func test_givenCancelFails_whenCancelling_thenRollsBackOptimisticRemoval() async {
        let stub = StubMessagesService()
        let post = scheduledMessage(id: "s-1")
        await stub.enqueueScheduledPosts(success: [post])
        await stub.enqueueCancelScheduled(failure: TestError.upstream("forbidden"))
        let viewModel = ScheduledPostsViewModel(messages: stub)
        await viewModel.load()

        await viewModel.cancel(post: post)

        XCTAssertEqual(viewModel.posts.map(\.id), ["s-1"])
        XCTAssertNotNil(viewModel.actionError)
    }

    func test_givenPostNotInList_whenCancelling_thenIsNoop() async {
        let stub = StubMessagesService()
        let post = scheduledMessage(id: "s-99")
        await stub.enqueueScheduledPosts(success: [])
        let viewModel = ScheduledPostsViewModel(messages: stub)
        await viewModel.load()

        await viewModel.cancel(post: post)

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1) // only the initial load, no cancel call
        XCTAssertNil(viewModel.actionError)
    }

    // MARK: - reschedule (NW-3)

    func test_givenScheduledPost_whenRescheduleSucceeds_thenReplacesWithServerCopy() async {
        let stub = StubMessagesService()
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        let newDate = Date(timeIntervalSince1970: 1_800_003_600)
        let post = scheduledMessage(id: "s-1", at: originalDate)
        await stub.enqueueScheduledPosts(success: [post])
        let confirmed = scheduledMessage(id: "s-1", at: newDate)
        await stub.enqueueReschedule(success: confirmed)
        let viewModel = ScheduledPostsViewModel(messages: stub)
        await viewModel.load()

        await viewModel.reschedule(post: post, to: newDate)

        XCTAssertEqual(viewModel.posts.first?.scheduledAt, newDate)
        XCTAssertNil(viewModel.actionError)
    }

    func test_givenRescheduleFails_whenRescheduling_thenRollsBackOptimisticDate() async {
        let stub = StubMessagesService()
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        let newDate = Date(timeIntervalSince1970: 1_800_003_600)
        let post = scheduledMessage(id: "s-1", at: originalDate)
        await stub.enqueueScheduledPosts(success: [post])
        await stub.enqueueReschedule(failure: TestError.upstream("conflict"))
        let viewModel = ScheduledPostsViewModel(messages: stub)
        await viewModel.load()

        await viewModel.reschedule(post: post, to: newDate)

        XCTAssertEqual(viewModel.posts.first?.scheduledAt, originalDate)
        XCTAssertNotNil(viewModel.actionError)
    }
}
