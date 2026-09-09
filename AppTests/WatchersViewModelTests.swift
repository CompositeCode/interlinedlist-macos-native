// WatchersViewModelTests
//
// BDD-named tests for the M3 sharing panel view model, updated for
// work-consolidation.md G23 (issue #48):
//
//  • `load()` now reads `watchers(of:)`, the real access list, instead of
//    `watcherUsers(of:)`, which was a candidate search all along.
//  • Adding a person calls the real `addWatcher` (POST) rather than
//    re-purposing the role-change PUT, and a subscriber block raises the
//    upsell instead of an error banner.
//  • Picking someone goes through `watcherCandidates(of:search:limit:)`.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class WatchersViewModelTests: XCTestCase {

    private func makeViewModel(
        stub: StubListsService,
        eventBus: ListsEventBus = ListsEventBus()
    ) -> WatchersViewModel {
        WatchersViewModel(lists: stub, eventBus: eventBus, listId: "L1")
    }

    // MARK: - load

    func test_givenLoadedWatchers_whenLoading_thenPopulates() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", username: "alice", role: .editor)
        await stub.enqueueWatchers(success: [alice])
        let viewModel = makeViewModel(stub: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.watchers.map(\.userId), ["u1"])
        XCTAssertNil(viewModel.error)
        // The panel must read the access list, not the candidate search.
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.first?.kind, .watchers(listId: "L1"))
    }

    func test_givenEmptyResponse_whenLoading_thenLeavesEmpty() async {
        let stub = StubListsService()
        await stub.enqueueWatchers(success: [])
        let viewModel = makeViewModel(stub: stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.watchers.isEmpty)
    }

    func test_givenAPIFailure_whenLoading_thenSurfacesError() async {
        let stub = StubListsService()
        await stub.enqueueWatchers(failure: TestError.upstream("denied"))
        let viewModel = makeViewModel(stub: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.error as? TestError, .upstream("denied"))
    }

    // MARK: - setRole optimistic + rollback

    func test_givenRoleChange_whenSetRoleSucceeds_thenAppliesServerRole() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", username: "alice", role: .viewer)
        await stub.enqueueWatchers(success: [alice])
        let confirmed = ListsFixtures.watcher(userId: "u1", username: "alice", role: .editor)
        await stub.enqueueSetWatcher(success: confirmed)
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.setRole(userId: "u1", role: .editor)

        XCTAssertEqual(viewModel.watchers.first?.role, .editor)
        // Display fields survive: the route only answers `{ role }`.
        XCTAssertEqual(viewModel.watchers.first?.username, "alice")
    }

    func test_givenSetRoleFailure_whenSetRole_thenRollsBack() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", username: "alice", role: .viewer)
        await stub.enqueueWatchers(success: [alice])
        let failure = TestError.upstream("server-down")
        await stub.enqueueSetWatcher(failure: failure)
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.setRole(userId: "u1", role: .editor)

        XCTAssertEqual(viewModel.watchers.first?.role, .viewer)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    func test_givenSetRoleBlockedForFreeAccount_whenSetRole_thenRollsBackAndRaisesUpsell() async {
        // Upstream-failure variant: a 403 arrives as `subscriberRequired` and
        // must present as an upsell, never as a raw error banner.
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", username: "alice", role: .viewer)
        await stub.enqueueWatchers(success: [alice])
        await stub.enqueueSetWatcher(failure: ListsError.subscriberRequired)
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.setRole(userId: "u1", role: .editor)

        XCTAssertEqual(viewModel.watchers.first?.role, .viewer)
        XCTAssertTrue(viewModel.showSubscriberUpsell)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - remove

    func test_givenWatcher_whenRemoveSucceeds_thenDropsFromList() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1")
        await stub.enqueueWatchers(success: [alice])
        await stub.enqueueRemoveWatcherSuccess()
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.remove(userId: "u1")

        XCTAssertTrue(viewModel.watchers.isEmpty)
    }

    func test_givenRemoveFailure_whenRemoving_thenRestoresSnapshot() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1")
        await stub.enqueueWatchers(success: [alice])
        await stub.enqueueRemoveWatcher(failure: TestError.upstream("denied"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.remove(userId: "u1")

        XCTAssertEqual(viewModel.watchers.map(\.userId), ["u1"])
    }

    // MARK: - apply(event:)

    func test_givenEventForOtherList_whenApplied_thenIsNoop() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", role: .viewer)
        await stub.enqueueWatchers(success: [alice])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        viewModel.apply(event: .watcherChanged(
            listId: "OTHER",
            watcher: ListsFixtures.watcher(userId: "u1", role: .owner)
        ))

        XCTAssertEqual(viewModel.watchers.first?.role, .viewer)
    }

    func test_givenWatcherChangedEventForList_whenApplied_thenSwapsRole() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", role: .viewer)
        await stub.enqueueWatchers(success: [alice])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        viewModel.apply(event: .watcherChanged(
            listId: "L1",
            watcher: ListsFixtures.watcher(userId: "u1", role: .owner)
        ))

        XCTAssertEqual(viewModel.watchers.first?.role, .owner)
    }

    // MARK: - candidate search (G23)

    func test_givenMatchingPeople_whenSearchingCandidates_thenPopulatesCandidates() async {
        let stub = StubListsService()
        await stub.enqueueWatchers(success: [])
        await stub.enqueueWatcherCandidates(success: [ListsFixtures.candidate(id: "u9")])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.searchCandidates(query: "ada")

        XCTAssertEqual(viewModel.candidates.map(\.id), ["u9"])
        XCTAssertTrue(viewModel.hasSearchedOnce)
        let recorded = await stub.recorded
        XCTAssertEqual(
            recorded.last?.kind,
            .watcherCandidates(listId: "L1", search: "ada", limit: WatchersViewModel.candidatePageSize)
        )
    }

    func test_givenNobodyMatches_whenSearchingCandidates_thenLeavesCandidatesEmpty() async {
        // Boundary: the search resolved, it just matched nobody. The sheet
        // reads `hasSearchedOnce` to say so instead of "search for someone".
        let stub = StubListsService()
        await stub.enqueueWatchers(success: [])
        await stub.enqueueWatcherCandidates(success: [])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.searchCandidates(query: "nobody")

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.hasSearchedOnce)
        XCTAssertNil(viewModel.error)
    }

    func test_givenCandidateSearchFails_whenSearching_thenClearsCandidatesAndSurfacesError() async {
        let stub = StubListsService()
        await stub.enqueueWatchers(success: [])
        await stub.enqueueWatcherCandidates(success: [ListsFixtures.candidate(id: "u9")])
        await stub.enqueueWatcherCandidates(failure: TestError.upstream("boom"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()
        await viewModel.searchCandidates(query: "ada")

        await viewModel.searchCandidates(query: "ada")

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertEqual(viewModel.error as? TestError, .upstream("boom"))
    }

    // MARK: - addWatcher (G23)

    func test_givenCandidate_whenAddWatcherSucceeds_thenAppendsAndDropsCandidate() async {
        let stub = StubListsService()
        await stub.enqueueWatchers(success: [])
        await stub.enqueueWatcherCandidates(success: [ListsFixtures.candidate(id: "u9", username: "new-user")])
        await stub.enqueueAddWatcherSuccess()
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()
        await viewModel.searchCandidates(query: "new")

        await viewModel.addWatcher(candidate: ListsFixtures.candidate(id: "u9", username: "new-user"), role: .viewer)

        XCTAssertEqual(viewModel.watchers.map(\.userId), ["u9"])
        XCTAssertEqual(viewModel.watchers.first?.role, .viewer)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        // The POST route is the one that gets hit, with the notify default.
        let recorded = await stub.recorded
        XCTAssertEqual(
            recorded.last?.kind,
            .addWatcher(listId: "L1", userId: "u9", role: .viewer, notify: true)
        )
    }

    func test_givenAlreadyAWatcher_whenAddingAgain_thenRejectsWithoutCallingService() async {
        // Invalid-input member: the guard fires before any service call.
        let stub = StubListsService()
        let existing = ListsFixtures.watcher(userId: "u9", username: "new-user", role: .viewer)
        await stub.enqueueWatchers(success: [existing])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()
        let callsBefore = await stub.recorded.count

        await viewModel.addWatcher(candidate: ListsFixtures.candidate(id: "u9"), role: .editor)

        XCTAssertEqual(viewModel.error as? WatchersError, .alreadyWatcher)
        XCTAssertEqual(viewModel.watchers.map(\.userId), ["u9"])
        let callsAfter = await stub.recorded.count
        XCTAssertEqual(callsAfter, callsBefore, "No service call may be made for a duplicate add.")
    }

    func test_givenAddWatcherFails_whenAddingWatcher_thenRollsBackSnapshot() async {
        let stub = StubListsService()
        let existing = ListsFixtures.watcher(userId: "u1", username: "alice", role: .viewer)
        await stub.enqueueWatchers(success: [existing])
        await stub.enqueueAddWatcher(failure: TestError.upstream("boom"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.addWatcher(candidate: ListsFixtures.candidate(id: "u9"), role: .viewer)

        XCTAssertEqual(viewModel.watchers.map(\.userId), ["u1"])
        XCTAssertNotNil(viewModel.error)
    }

    func test_givenFreeAccount_whenAddingWatcher_thenRollsBackAndRaisesUpsell() async {
        // Upstream-failure member: the subscriber gate is a 403 the service
        // projects onto `ListsError.subscriberRequired`.
        let stub = StubListsService()
        await stub.enqueueWatchers(success: [])
        await stub.enqueueAddWatcher(failure: ListsError.subscriberRequired)
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.addWatcher(candidate: ListsFixtures.candidate(id: "u9"), role: .editor)

        XCTAssertTrue(viewModel.watchers.isEmpty, "The provisional row must be rolled back.")
        XCTAssertTrue(viewModel.showSubscriberUpsell)
        XCTAssertNil(viewModel.error, "The gate presents as an upsell, not an error.")
    }

    func test_givenUpsellShown_whenDismissed_thenClearsFlag() async {
        let stub = StubListsService()
        await stub.enqueueWatchers(success: [])
        await stub.enqueueAddWatcher(failure: ListsError.subscriberRequired)
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()
        await viewModel.addWatcher(candidate: ListsFixtures.candidate(id: "u9"), role: .editor)

        viewModel.dismissSubscriberUpsell()

        XCTAssertFalse(viewModel.showSubscriberUpsell)
    }
}
