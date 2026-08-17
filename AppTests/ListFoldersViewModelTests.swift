// ListFoldersViewModelTests
//
// BDD-named tests for the list-folders view model (work-consolidation.md G6).
// Covers the required quartet plus the subscriber-gate and the delete
// rollback:
//   - happy: load populates the tree.
//   - invalid input: create with a name the service rejects
//     (`invalidName`) surfaces the error, not the upsell.
//   - upstream failure: load failure surfaces the error + hasLoadedOnce.
//   - empty / boundary: load with an empty tree reports empty +
//     hasLoadedOnce.
//   - create happy: create + tree refetch replaces the tree.
//   - subscriber gate: a `subscriberRequired` create raises the upsell,
//     not an error.
//   - delete happy: optimistic prune + service call.
//   - delete rollback: failure restores the pruned subtree.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ListFoldersViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel() -> (ListFoldersViewModel, StubListFoldersService) {
        let service = StubListFoldersService()
        let vm = ListFoldersViewModel(service: service)
        return (vm, service)
    }

    private func folder(_ id: String, name: String? = nil, parentId: String? = nil) -> ListFolder {
        ListFolder(id: id, name: name ?? "Folder \(id)", parentId: parentId, createdAt: nil, updatedAt: nil)
    }

    private func node(_ id: String, children: [ListFolderNode] = []) -> ListFolderNode {
        ListFolderNode(folder: folder(id), children: children)
    }

    // MARK: - load

    func test_givenFolders_whenLoading_thenTreePopulates() async {
        let (vm, service) = makeViewModel()
        await service.enqueueTree(success: [node("f1"), node("f2", children: [node("f3")])])

        await vm.load()

        XCTAssertEqual(vm.tree.map(\.id), ["f1", "f2"])
        XCTAssertEqual(vm.tree.last?.children.map(\.id), ["f3"])
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    func test_givenEmptyTree_whenLoading_thenReportsEmptyAndHasLoadedOnce() async {
        let (vm, service) = makeViewModel()
        await service.enqueueTree(success: [])

        await vm.load()

        XCTAssertTrue(vm.tree.isEmpty)
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    func test_givenTreeFailure_whenLoading_thenSurfacesErrorAndHasLoadedOnce() async {
        let (vm, service) = makeViewModel()
        await service.enqueueTree(failure: TestError.upstream("net"))

        await vm.load()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    // MARK: - create

    func test_givenSubscriber_whenCreating_thenTreeRefetchedAndReplaced() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(tree: [node("f1")])
        await service.enqueueCreate(success: folder("f2", name: "New"))
        // The post-create tree refetch returns the updated tree.
        await service.enqueueTree(success: [node("f1"), node("f2")])

        let created = await vm.create(name: "New", parentId: nil)

        XCTAssertEqual(created?.id, "f2")
        XCTAssertEqual(vm.tree.map(\.id), ["f1", "f2"])
        XCTAssertFalse(vm.showSubscriberUpsell)
        XCTAssertNil(vm.error)
    }

    func test_givenNonSubscriber_whenCreating_thenRaisesUpsellNotError() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(tree: [node("f1")])
        await service.enqueueCreate(failure: ListFoldersError.subscriberRequired)

        let created = await vm.create(name: "New", parentId: nil)

        XCTAssertNil(created)
        XCTAssertTrue(vm.showSubscriberUpsell)
        XCTAssertNil(vm.error, "The subscriber gate must not surface as a raw error")
        // The tree is untouched (no refetch on the gated path).
        XCTAssertEqual(vm.tree.map(\.id), ["f1"])
    }

    func test_givenInvalidName_whenCreating_thenSurfacesErrorNotUpsell() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(tree: [])
        await service.enqueueCreate(failure: ListFoldersError.invalidName)

        let created = await vm.create(name: "", parentId: nil)

        XCTAssertNil(created)
        XCTAssertFalse(vm.showSubscriberUpsell)
        XCTAssertEqual(vm.error as? ListFoldersError, .invalidName)
    }

    // MARK: - delete

    func test_givenFolder_whenDeleting_thenPrunesSubtreeAndCallsService() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(tree: [node("f1"), node("f2", children: [node("f3")])])
        await service.enqueueDeleteSuccess()

        await vm.delete(id: "f2")

        XCTAssertEqual(vm.tree.map(\.id), ["f1"], "Deleting f2 removes it and its child f3")
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains { if case .delete(let id) = $0.kind { return id == "f2" } else { return false } })
    }

    func test_givenDeleteFailure_whenDeleting_thenRestoresSubtreeAndSurfacesError() async {
        let (vm, service) = makeViewModel()
        let initial = [node("f1"), node("f2", children: [node("f3")])]
        vm.seedForTest(tree: initial)
        await service.enqueueDelete(failure: TestError.upstream("net"))

        await vm.delete(id: "f2")

        XCTAssertEqual(vm.tree.map(\.id), ["f1", "f2"], "Failed delete must restore the pruned subtree")
        XCTAssertEqual(vm.tree.last?.children.map(\.id), ["f3"])
        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
    }

    // MARK: - rename / move

    func test_givenFolder_whenRenaming_thenTreeRefetched() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(tree: [node("f1")])
        await service.enqueueRename(success: folder("f1", name: "Renamed"))
        await service.enqueueTree(success: [node("f1")])

        await vm.rename(id: "f1", to: "Renamed")

        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains { if case .rename(let id, let name) = $0.kind { return id == "f1" && name == "Renamed" } else { return false } })
    }

    func test_givenFolder_whenMoving_thenTreeRefetched() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(tree: [node("f1"), node("f2")])
        await service.enqueueMove(success: folder("f2", parentId: "f1"))
        await service.enqueueTree(success: [node("f1", children: [node("f2")])])

        await vm.move(id: "f2", toParent: "f1")

        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.tree.map(\.id), ["f1"])
        XCTAssertEqual(vm.tree.first?.children.map(\.id), ["f2"])
    }
}
