// OwnedListsSWRViewModelTests
//
// Stale-while-revalidate (SWR) view-model tests for the M3 owned-lists
// root (PLAN.md §5, PASS 2). Exercises the cache-first paint added in
// PASS 2 via `StubListsService.setCachedMyLists`. View-model only — no
// SwiftUI rendering.
//
// Quartet per behavior: cache-present happy path, cold-cache path,
// refresh-error-with-cache path, and the freshness-TTL skip.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OwnedListsSWRViewModelTests: XCTestCase {

    // MARK: - Cache present (paint-first, no blocking spinner)

    func test_givenCachedLists_whenInitialLoad_thenPaintsCacheWithoutBlockingSpinner() async {
        // Given — a populated cache and a slow-but-successful network page.
        let stub = StubListsService()
        let cached = [ListsFixtures.ownedList(id: "L1", title: "Cached")]
        await stub.setCachedMyLists(cached)
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([
            ListsFixtures.ownedList(id: "L1", title: "Fresh"),
            ListsFixtures.ownedList(id: "L2", title: "New")
        ]))
        let viewModel = OwnedListsViewModel(lists: stub)

        // When
        await viewModel.initialLoad()

        // Then — the cache painted, the blocking spinner never showed, and the
        // authoritative network page replaced it.
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertEqual(viewModel.lists_loaded.map(\.id), ["L1", "L2"])
        XCTAssertEqual(viewModel.lists_loaded.map(\.title), ["Fresh", "New"])
        XCTAssertNil(viewModel.error)
        XCTAssertNotNil(viewModel.lastRefreshedAt)
    }

    // MARK: - Cold cache (blocking spinner until network returns)

    func test_givenEmptyCache_whenInitialLoad_thenUsesBlockingSpinnerThenData() async {
        // Given — cold cache; the network provides the first data.
        let stub = StubListsService()
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([
            ListsFixtures.ownedList(id: "L1")
        ]))
        let viewModel = OwnedListsViewModel(lists: stub)

        // When
        await viewModel.initialLoad()

        // Then — after settle: data present, no residual spinners, no
        // non-blocking refresh flag (this was a cold cold-start path).
        XCTAssertEqual(viewModel.lists_loaded.map(\.id), ["L1"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.refreshFailed)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Refresh error with cache (keep rows, non-blocking flag)

    func test_givenCachedListsAndRefreshFails_whenInitialLoad_thenKeepsRowsAndSetsRefreshFailed() async {
        // Given — a populated cache and a failing network revalidation.
        let stub = StubListsService()
        let cached = [ListsFixtures.ownedList(id: "L1", title: "Cached")]
        await stub.setCachedMyLists(cached)
        await stub.enqueueMyLists(failure: TestError.upstream("revalidate down"))
        let viewModel = OwnedListsViewModel(lists: stub)

        // When
        await viewModel.initialLoad()

        // Then — the list keeps its cached rows; a non-blocking flag is set;
        // the blocking `error` is NOT set (the list is never blanked).
        XCTAssertEqual(viewModel.lists_loaded.map(\.id), ["L1"])
        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    // MARK: - Cold cache + failure → today's blocking error state

    func test_givenEmptyCacheAndNetworkFails_whenInitialLoad_thenSurfacesBlockingError() async {
        // Given — cold cache and a failing network load: the classic error state.
        let stub = StubListsService()
        await stub.enqueueMyLists(failure: TestError.upstream("boom"))
        let viewModel = OwnedListsViewModel(lists: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertTrue(viewModel.lists_loaded.isEmpty)
        XCTAssertEqual(viewModel.error as? TestError, .upstream("boom"))
        XCTAssertFalse(viewModel.refreshFailed)
    }

    // MARK: - Freshness TTL

    func test_givenFreshlyRefreshed_whenCheckingShouldRefresh_thenSkipsRevalidation() async {
        // Given — a successful load just set `lastRefreshedAt`.
        let stub = StubListsService()
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([
            ListsFixtures.ownedList(id: "L1")
        ]))
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()

        // Then — within the TTL, a re-appearance should trust the cache.
        XCTAssertFalse(viewModel.shouldRefresh)
    }

    func test_givenNeverRefreshed_whenCheckingShouldRefresh_thenRevalidates() {
        // Boundary: a brand-new VM has no `lastRefreshedAt` → must revalidate.
        let stub = StubListsService()
        let viewModel = OwnedListsViewModel(lists: stub)
        XCTAssertTrue(viewModel.shouldRefresh)
    }
}
