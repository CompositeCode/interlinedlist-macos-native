// ScheduledPostsSWRViewModelTests
//
// Stale-while-revalidate (SWR) view-model tests for the Scheduled posts
// list (PLAN.md §5, PASS 2). Exercises the cache-first paint added in
// PASS 2 via `StubMessagesService.setCachedScheduledPosts`. View-model
// only — no SwiftUI rendering.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ScheduledPostsSWRViewModelTests: XCTestCase {

    private func scheduledMessage(id: String, text: String = "queued") -> Message {
        Message(
            id: id,
            author: MessageFixtures.author(),
            text: text,
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
            scheduledAt: Date().addingTimeInterval(3600)
        )
    }

    // MARK: - Cache present

    func test_givenCachedPosts_whenLoading_thenPaintsCacheWithoutBlockingSpinner() async {
        // Given — a populated cache and a fresh network payload.
        let stub = StubMessagesService()
        await stub.setCachedScheduledPosts([scheduledMessage(id: "s-1", text: "cached")])
        await stub.enqueueScheduledPosts(success: [
            scheduledMessage(id: "s-1", text: "fresh"),
            scheduledMessage(id: "s-2", text: "new")
        ])
        let viewModel = ScheduledPostsViewModel(messages: stub)

        // When
        await viewModel.load()

        // Then — cache painted (hasLoadedOnce), no blocking spinner, network
        // replaced it authoritatively.
        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertEqual(viewModel.posts.map(\.id), ["s-1", "s-2"])
        XCTAssertNil(viewModel.error)
        XCTAssertNotNil(viewModel.lastRefreshedAt)
    }

    // MARK: - Cold cache

    func test_givenEmptyCache_whenLoading_thenUsesBlockingSpinnerThenData() async {
        // Given
        let stub = StubMessagesService()
        await stub.enqueueScheduledPosts(success: [scheduledMessage(id: "s-1")])
        let viewModel = ScheduledPostsViewModel(messages: stub)

        // When
        await viewModel.load()

        // Then
        XCTAssertEqual(viewModel.posts.map(\.id), ["s-1"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.refreshFailed)
    }

    // MARK: - Refresh error with cache

    func test_givenCachedPostsAndRefreshFails_whenLoading_thenKeepsPostsAndSetsRefreshFailed() async {
        // Given
        let stub = StubMessagesService()
        await stub.setCachedScheduledPosts([scheduledMessage(id: "s-1", text: "cached")])
        await stub.enqueueScheduledPosts(failure: TestError.upstream("revalidate down"))
        let viewModel = ScheduledPostsViewModel(messages: stub)

        // When
        await viewModel.load()

        // Then — posts kept; non-blocking flag set; blocking error unset.
        XCTAssertEqual(viewModel.posts.map(\.id), ["s-1"])
        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Cold cache + failure → blocking error

    func test_givenEmptyCacheAndNetworkFails_whenLoading_thenSurfacesBlockingError() async {
        // Given
        let stub = StubMessagesService()
        await stub.enqueueScheduledPosts(failure: TestError.upstream("boom"))
        let viewModel = ScheduledPostsViewModel(messages: stub)

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertEqual(viewModel.error as? TestError, .upstream("boom"))
        XCTAssertFalse(viewModel.refreshFailed)
    }

    // MARK: - Freshness TTL

    func test_givenFreshlyRefreshed_whenCheckingShouldRefresh_thenSkipsRevalidation() async {
        let stub = StubMessagesService()
        await stub.enqueueScheduledPosts(success: [scheduledMessage(id: "s-1")])
        let viewModel = ScheduledPostsViewModel(messages: stub)
        await viewModel.load()
        XCTAssertFalse(viewModel.shouldRefresh)
    }
}
