// WatchersViewModelTests
//
// BDD-named tests for the M3 sharing panel view model.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class WatchersViewModelTests: XCTestCase {

    // MARK: - load

    func test_givenLoadedWatchers_whenLoading_thenPopulates() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", username: "alice", role: .editor)
        await stub.enqueueWatcherUsers(success: [alice])
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.load()

        XCTAssertEqual(viewModel.watchers.map(\.userId), ["u1"])
        XCTAssertNil(viewModel.error)
    }

    func test_givenEmptyResponse_whenLoading_thenLeavesEmpty() async {
        let stub = StubListsService()
        await stub.enqueueWatcherUsers(success: [])
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.load()

        XCTAssertTrue(viewModel.watchers.isEmpty)
    }

    func test_givenAPIFailure_whenLoading_thenSurfacesError() async {
        let stub = StubListsService()
        await stub.enqueueWatcherUsers(failure: TestError.upstream("denied"))
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.load()

        XCTAssertEqual(viewModel.error as? TestError, .upstream("denied"))
    }

    // MARK: - setRole optimistic + rollback

    func test_givenRoleChange_whenSetRoleSucceeds_thenReplacesWithServerCopy() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", username: "alice", role: .viewer)
        await stub.enqueueWatcherUsers(success: [alice])
        let confirmed = ListsFixtures.watcher(userId: "u1", username: "alice", role: .editor)
        await stub.enqueueSetWatcher(success: confirmed)
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.load()

        await viewModel.setRole(userId: "u1", role: .editor)

        XCTAssertEqual(viewModel.watchers.first?.role, .editor)
    }

    func test_givenSetRoleFailure_whenSetRole_thenRollsBack() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", username: "alice", role: .viewer)
        await stub.enqueueWatcherUsers(success: [alice])
        let failure = TestError.upstream("server-down")
        await stub.enqueueSetWatcher(failure: failure)
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.load()

        await viewModel.setRole(userId: "u1", role: .editor)

        XCTAssertEqual(viewModel.watchers.first?.role, .viewer)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - remove

    func test_givenWatcher_whenRemoveSucceeds_thenDropsFromList() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1")
        await stub.enqueueWatcherUsers(success: [alice])
        await stub.enqueueRemoveWatcherSuccess()
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.load()

        await viewModel.remove(userId: "u1")

        XCTAssertTrue(viewModel.watchers.isEmpty)
    }

    func test_givenRemoveFailure_whenRemoving_thenRestoresSnapshot() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1")
        await stub.enqueueWatcherUsers(success: [alice])
        await stub.enqueueRemoveWatcher(failure: TestError.upstream("denied"))
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.load()

        await viewModel.remove(userId: "u1")

        XCTAssertEqual(viewModel.watchers.map(\.userId), ["u1"])
    }

    // MARK: - apply(event:)

    func test_givenEventForOtherList_whenApplied_thenIsNoop() async {
        let stub = StubListsService()
        let alice = ListsFixtures.watcher(userId: "u1", role: .viewer)
        await stub.enqueueWatcherUsers(success: [alice])
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
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
        await stub.enqueueWatcherUsers(success: [alice])
        let viewModel = WatchersViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.load()

        viewModel.apply(event: .watcherChanged(
            listId: "L1",
            watcher: ListsFixtures.watcher(userId: "u1", role: .owner)
        ))

        XCTAssertEqual(viewModel.watchers.first?.role, .owner)
    }
}
