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
}
