// WatchedListsViewModelTests
//
// BDD-named tests for the "Shared with me" sidebar section
// (work-consolidation.md G23 / issue #48).
//
// The load-failure case carries the issue's acceptance criterion directly:
// this view model owns its own error, so a failing `GET /api/lists/watching`
// cannot blank or block the owned-lists section beside it.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class WatchedListsViewModelTests: XCTestCase {

    // MARK: - load

    func test_givenSharedLists_whenLoading_thenPopulatesInServerOrder() async {
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1", title: "Shows", role: .collaborator),
            ListsFixtures.watchedList(id: "L2", title: "Videos", role: .watcher)
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.watched.map(\.id), ["L1", "L2"])
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.hasLoadedOnce)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.first?.kind, .watching(limit: WatchedListsViewModel.pageSize, offset: 0))
    }

    func test_givenNothingShared_whenLoading_thenLeavesEmptyWithoutError() async {
        // Boundary: zero watched lists is a normal state, not a failure — the
        // sidebar section renders nothing rather than an empty-state row.
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([]))
        let viewModel = WatchedListsViewModel(lists: stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.watched.isEmpty)
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.hasLoadedOnce)
    }

    func test_givenWatchingFails_whenLoading_thenSurfacesErrorScopedToThisSection() async {
        // Upstream failure: the error lands here, on the shared-with-me view
        // model only. The owned-lists sidebar has its own model and its own
        // state, so it keeps rendering (issue #48 acceptance criteria).
        let stub = StubListsService()
        await stub.enqueueWatching(failure: TestError.upstream("watching-500"))
        let viewModel = WatchedListsViewModel(lists: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.error as? TestError, .upstream("watching-500"))
        XCTAssertTrue(viewModel.watched.isEmpty)
    }

    func test_givenLoadedListsThenFailure_whenReloading_thenKeepsExistingRows() async {
        // A flaky refresh must not cost the user their shared lists.
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1")
        ]))
        await stub.enqueueWatching(failure: TestError.upstream("flaky"))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        await viewModel.load()

        XCTAssertEqual(viewModel.watched.map(\.id), ["L1"])
        XCTAssertEqual(viewModel.error as? TestError, .upstream("flaky"))
    }

    // MARK: - grouping

    func test_givenMixedRoles_whenGrouping_thenOrdersByRoleAndOmitsEmptyGroups() async {
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1", role: .collaborator),
            ListsFixtures.watchedList(id: "L2", role: .watcher),
            ListsFixtures.watchedList(id: "L3", role: .collaborator)
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        let groups = viewModel.groupedByRole

        // `manager` has no rows, so it is absent entirely.
        XCTAssertEqual(groups.map(\.role), [.watcher, .collaborator])
        XCTAssertEqual(groups.first(where: { $0.role == .collaborator })?.lists.map(\.id), ["L1", "L3"])
    }

    func test_givenNoLists_whenGrouping_thenReturnsNoGroups() async {
        // Boundary for the grouping helper on its own.
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        XCTAssertTrue(viewModel.groupedByRole.isEmpty)
    }

    // MARK: - selection lookup

    func test_givenLoadedLists_whenLookingUpKnownID_thenReturnsEntry() async {
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1", title: "Shows")
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        XCTAssertEqual(viewModel.list(withID: "L1")?.title, "Shows")
    }

    func test_givenUnknownOrNilID_whenLookingUp_thenReturnsNil() async {
        // Invalid input: an owned-list id (or no selection) must miss here so
        // the rows pane falls through to the owned collection.
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1")
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        XCTAssertNil(viewModel.list(withID: "OWNED-1"))
        XCTAssertNil(viewModel.list(withID: nil))
    }

    // MARK: - paging

    func test_givenMorePages_whenLoadingMore_thenAppends() async {
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage(
            [ListsFixtures.watchedList(id: "L1")],
            hasMore: true,
            nextOffset: 50
        ))
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L2")
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        await viewModel.loadMore()

        XCTAssertEqual(viewModel.watched.map(\.id), ["L1", "L2"])
        XCTAssertFalse(viewModel.hasMore)
    }

    func test_givenNoMorePages_whenLoadingMore_thenIsNoop() async {
        // Boundary: `loadMore` on a complete list must not spend a request.
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1")
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()
        let callsBefore = await stub.recorded.count

        await viewModel.loadMore()

        let callsAfter = await stub.recorded.count
        XCTAssertEqual(callsAfter, callsBefore)
    }

    // MARK: - freshness TTL

    func test_givenNeverLoaded_whenAskingShouldRefresh_thenIsTrue() {
        let viewModel = WatchedListsViewModel(lists: StubListsService())

        XCTAssertTrue(viewModel.shouldRefresh)
    }

    func test_givenJustLoaded_whenAskingShouldRefresh_thenIsFalse() async {
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([]))
        let viewModel = WatchedListsViewModel(lists: stub)

        await viewModel.load()

        XCTAssertFalse(viewModel.shouldRefresh)
    }

    // MARK: - apply(event:)

    func test_givenListDeletedEvent_whenApplied_thenDropsTheRow() async {
        // Losing access (or the owner deleting the list) must drop it.
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1"),
            ListsFixtures.watchedList(id: "L2")
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        viewModel.apply(event: .listDeleted(id: "L1"))

        XCTAssertEqual(viewModel.watched.map(\.id), ["L2"])
    }

    func test_givenListCreatedEvent_whenApplied_thenIsNoop() async {
        // A list *this* account creates belongs to the owned section, never
        // to shared-with-me.
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1")
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        viewModel.apply(event: .listCreated(ListsFixtures.ownedList(id: "NEW")))

        XCTAssertEqual(viewModel.watched.map(\.id), ["L1"])
    }

    func test_givenListUpdatedEventForWatchedList_whenApplied_thenKeepsOwnerAndRole() async {
        // The event carries only the list, so the owner and the caller's role
        // must survive the swap.
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1", title: "Old", role: .collaborator)
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        viewModel.apply(event: .listUpdated(ListsFixtures.ownedList(id: "L1", title: "New")))

        XCTAssertEqual(viewModel.watched.first?.title, "New")
        XCTAssertEqual(viewModel.watched.first?.role, .collaborator)
        XCTAssertEqual(viewModel.watched.first?.owner?.username, "adron")
    }

    func test_givenEventForUnknownList_whenApplied_thenIsNoop() async {
        let stub = StubListsService()
        await stub.enqueueWatching(success: ListsFixtures.watchedListsPage([
            ListsFixtures.watchedList(id: "L1", title: "Shows")
        ]))
        let viewModel = WatchedListsViewModel(lists: stub)
        await viewModel.load()

        viewModel.apply(event: .listUpdated(ListsFixtures.ownedList(id: "OTHER", title: "Nope")))

        XCTAssertEqual(viewModel.watched.map(\.title), ["Shows"])
    }
}
