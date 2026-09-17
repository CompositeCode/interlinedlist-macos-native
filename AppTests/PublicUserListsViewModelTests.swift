// PublicUserListsViewModelTests
//
// BDD quartet for the public-lists column on a profile (GitHub #44 / G32).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class PublicUserListsViewModelTests: XCTestCase {

    private func summary(_ id: String, _ title: String) -> ListSummary {
        ListSummary(id: id, title: title, description: nil)
    }

    private func page(_ lists: [ListSummary]) -> ListsPage {
        ListsPage(lists: lists, hasMore: false, nextOffset: nil)
    }

    // MARK: - Happy path

    func test_givenPublicLists_whenLoading_thenRowsArriveForThatHandle() async {
        // Given
        let stub = StubListsService()
        await stub.enqueuePublicLists(success: page([summary("L1", "Films"), summary("L2", "Books")]))
        let viewModel = PublicUserListsViewModel(lists: stub)

        // When
        await viewModel.load(username: "ada")

        // Then
        XCTAssertEqual(viewModel.listsLoaded.map(\.id), ["L1", "L2"])
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        guard case .publicLists(let username, _, _)? = recorded.first?.kind else {
            return XCTFail("expected publicLists, got \(String(describing: recorded.first))")
        }
        XCTAssertEqual(username, "ada")
    }

    // MARK: - Invalid input — never spend a round-trip on an empty handle

    func test_givenBlankHandle_whenLoading_thenNoCallIsMade() async {
        let stub = StubListsService()
        let viewModel = PublicUserListsViewModel(lists: stub)

        await viewModel.load(username: "   ")

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertFalse(viewModel.hasLoaded, "nothing was asked, so nothing is known")
    }

    // MARK: - Upstream failure

    func test_givenServiceFailure_whenLoading_thenErrorIsSurfacedAndRowsAreCleared() async {
        let stub = StubListsService()
        await stub.enqueuePublicLists(failure: TestError.upstream("boom"))
        let viewModel = PublicUserListsViewModel(lists: stub)

        await viewModel.load(username: "ada")

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.listsLoaded.isEmpty)
        XCTAssertTrue(viewModel.hasLoaded, "the load completed — it completed badly")
    }

    // MARK: - Boundary — no public lists is not the same as not asked

    func test_givenNoPublicLists_whenLoading_thenEmptyIsDistinguishableFromUnasked() async {
        let stub = StubListsService()
        await stub.enqueuePublicLists(success: page([]))
        let viewModel = PublicUserListsViewModel(lists: stub)

        XCTAssertFalse(viewModel.hasLoaded)
        await viewModel.load(username: "ada")

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Watch

    func test_givenAPublicList_whenWatching_thenTheRowFlipsAndTheCallIsMade() async {
        let stub = StubListsService()
        await stub.enqueuePublicLists(success: page([summary("L1", "Films")]))
        await stub.enqueueWatch()
        let viewModel = PublicUserListsViewModel(lists: stub)
        await viewModel.load(username: "ada")

        await viewModel.watch(listID: "L1")

        XCTAssertTrue(viewModel.isWatching("L1"))
        XCTAssertFalse(viewModel.isWatchPending("L1"))
        XCTAssertNil(viewModel.watchErrors["L1"])
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.contains { if case .watch(let id) = $0.kind { return id == "L1" } else { return false } })
    }

    func test_givenAFailedWatch_whenWriting_thenTheOptimisticFlipRollsBack() async {
        // The rollback matters more than the optimism: a button that claims
        // success and silently did nothing is worse than a slow one.
        let stub = StubListsService()
        await stub.enqueuePublicLists(success: page([summary("L1", "Films")]))
        await stub.enqueueWatch(failure: TestError.upstream("nope"))
        let viewModel = PublicUserListsViewModel(lists: stub)
        await viewModel.load(username: "ada")

        await viewModel.watch(listID: "L1")

        XCTAssertFalse(viewModel.isWatching("L1"), "the optimistic flip is undone")
        XCTAssertNotNil(viewModel.watchErrors["L1"], "and the failure is reported on that row")
    }

    func test_givenAlreadyWatching_whenWatchingAgain_thenNoSecondCallIsMade() async {
        // Boundary: a double-press must not fire two writes.
        let stub = StubListsService()
        await stub.enqueuePublicLists(success: page([summary("L1", "Films")]))
        await stub.enqueueWatch()
        let viewModel = PublicUserListsViewModel(lists: stub)
        await viewModel.load(username: "ada")

        await viewModel.watch(listID: "L1")
        await viewModel.watch(listID: "L1")

        let watchCalls = await stub.recorded.filter { if case .watch = $0.kind { return true } else { return false } }
        XCTAssertEqual(watchCalls.count, 1)
    }

    func test_givenAFailedWatchOnOneRow_whenAnotherSucceeds_thenTheErrorStaysOnItsOwnRow() async {
        // The failure is reported against the row that caused it, not the column.
        let stub = StubListsService()
        await stub.enqueuePublicLists(success: page([summary("L1", "Films"), summary("L2", "Books")]))
        await stub.enqueueWatch(failure: TestError.upstream("nope"))
        await stub.enqueueWatch()
        let viewModel = PublicUserListsViewModel(lists: stub)
        await viewModel.load(username: "ada")

        await viewModel.watch(listID: "L1")
        await viewModel.watch(listID: "L2")

        XCTAssertNotNil(viewModel.watchErrors["L1"])
        XCTAssertNil(viewModel.watchErrors["L2"])
        XCTAssertFalse(viewModel.isWatching("L1"))
        XCTAssertTrue(viewModel.isWatching("L2"))
    }
}
