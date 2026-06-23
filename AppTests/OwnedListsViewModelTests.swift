// OwnedListsViewModelTests
//
// BDD-named view-model tests for the M3 owned-lists root.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OwnedListsViewModelTests: XCTestCase {

    // MARK: - initialLoad

    func test_givenLoadedLists_whenInitialLoad_thenPopulatesList() async {
        // Given
        let stub = StubListsService()
        let list = ListsFixtures.ownedList(id: "L1", title: "Books")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([list]))
        let viewModel = OwnedListsViewModel(lists: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertEqual(viewModel.lists_loaded.map(\.id), ["L1"])
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_givenEmptyResponse_whenInitialLoad_thenLeavesListEmpty() async {
        // Given — empty/boundary case.
        let stub = StubListsService()
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([]))
        let viewModel = OwnedListsViewModel(lists: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertTrue(viewModel.lists_loaded.isEmpty)
        XCTAssertNil(viewModel.error)
    }

    func test_givenAPIFailure_whenInitialLoad_thenSurfacesError() async {
        // Given — upstream API failure case.
        let stub = StubListsService()
        let failure = TestError.upstream("boom")
        await stub.enqueueMyLists(failure: failure)
        let viewModel = OwnedListsViewModel(lists: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.lists_loaded.isEmpty)
    }

    func test_givenHasMoreFlag_whenInitialLoad_thenSurfacesNextOffset() async {
        // Pagination boundary.
        let stub = StubListsService()
        let list = ListsFixtures.ownedList(id: "L1")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([list], hasMore: true, nextOffset: 50))
        let viewModel = OwnedListsViewModel(lists: stub)

        await viewModel.initialLoad()

        XCTAssertTrue(viewModel.hasMore)
        XCTAssertEqual(viewModel.nextOffset, 50)
    }

    // MARK: - deleteList

    func test_givenSelectedList_whenDeleting_thenRemovesAndClearsSelection() async {
        let stub = StubListsService()
        let list = ListsFixtures.ownedList(id: "L1")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([list]))
        await stub.enqueueDeleteSuccess()
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()
        viewModel.select(id: "L1")

        await viewModel.deleteList(id: "L1")

        XCTAssertTrue(viewModel.lists_loaded.isEmpty)
        XCTAssertNil(viewModel.selectedListID)
        XCTAssertNil(viewModel.error)
    }

    func test_givenDeleteFailure_whenDeleting_thenRestoresSnapshotAndSurfacesError() async {
        let stub = StubListsService()
        let list = ListsFixtures.ownedList(id: "L1")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([list]))
        let failure = TestError.upstream("denied")
        await stub.enqueueDelete(failure: failure)
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()

        await viewModel.deleteList(id: "L1")

        XCTAssertEqual(viewModel.lists_loaded.map(\.id), ["L1"])
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - refresh (GitHub-backed)

    func test_givenGitHubBackedSelection_whenChecking_thenCanRefresh() async {
        let stub = StubListsService()
        let list = ListsFixtures.ownedList(
            id: "L1",
            gitHubSource: GitHubListSource(repository: "owner/repo")
        )
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([list]))
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()
        viewModel.select(id: "L1")

        XCTAssertTrue(viewModel.canRefreshSelectedList)
    }

    func test_givenPlainList_whenChecking_thenCannotRefresh() async {
        let stub = StubListsService()
        let list = ListsFixtures.ownedList(id: "L1")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([list]))
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()
        viewModel.select(id: "L1")

        XCTAssertFalse(viewModel.canRefreshSelectedList)
    }

    func test_givenGitHubList_whenRefreshing_thenReplacesCachedCopy() async {
        let stub = StubListsService()
        let original = ListsFixtures.ownedList(
            id: "L1",
            title: "Old",
            gitHubSource: GitHubListSource(repository: "o/r")
        )
        let refreshed = ListsFixtures.ownedList(
            id: "L1",
            title: "Refreshed",
            gitHubSource: GitHubListSource(repository: "o/r")
        )
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([original]))
        await stub.enqueueRefresh(success: refreshed)
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()

        await viewModel.refreshList(id: "L1")

        XCTAssertEqual(viewModel.lists_loaded.first?.title, "Refreshed")
    }

    // MARK: - apply(event:)

    func test_givenListCreatedEvent_whenApplied_thenPrepends() async {
        let stub = StubListsService()
        let existing = ListsFixtures.ownedList(id: "L1")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([existing]))
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()
        let newList = ListsFixtures.ownedList(id: "L2", title: "New")

        viewModel.apply(event: .listCreated(newList))

        XCTAssertEqual(viewModel.lists_loaded.map(\.id), ["L2", "L1"])
    }

    func test_givenListUpdatedEvent_whenApplied_thenSwapsInPlace() async {
        let stub = StubListsService()
        let original = ListsFixtures.ownedList(id: "L1", title: "Old")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([original]))
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()
        let updated = ListsFixtures.ownedList(id: "L1", title: "New")

        viewModel.apply(event: .listUpdated(updated))

        XCTAssertEqual(viewModel.lists_loaded.first?.title, "New")
    }

    func test_givenListDeletedEvent_whenApplied_thenRemovesAndClearsSelection() async {
        let stub = StubListsService()
        let list = ListsFixtures.ownedList(id: "L1")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([list]))
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()
        viewModel.select(id: "L1")

        viewModel.apply(event: .listDeleted(id: "L1"))

        XCTAssertTrue(viewModel.lists_loaded.isEmpty)
        XCTAssertNil(viewModel.selectedListID)
    }

    func test_givenUnrelatedRowEvent_whenApplied_thenIsNoop() async {
        // Boundary — non-list-level events are no-ops here.
        let stub = StubListsService()
        let list = ListsFixtures.ownedList(id: "L1")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([list]))
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()

        viewModel.apply(event: .rowCreated(listId: "L1", row: ListsFixtures.row(id: "R1")))

        XCTAssertEqual(viewModel.lists_loaded.map(\.id), ["L1"])
    }

    // MARK: - nested-list helpers

    func test_givenParentAndChildren_whenAskingForRoots_thenReturnsOnlyParent() async {
        let stub = StubListsService()
        let parent = ListsFixtures.ownedList(id: "P")
        let child = ListsFixtures.ownedList(id: "C", parentID: "P")
        await stub.enqueueMyLists(success: ListsFixtures.ownedListsPage([parent, child]))
        let viewModel = OwnedListsViewModel(lists: stub)
        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.roots().map(\.id), ["P"])
        XCTAssertEqual(viewModel.children(of: "P").map(\.id), ["C"])
    }
}
