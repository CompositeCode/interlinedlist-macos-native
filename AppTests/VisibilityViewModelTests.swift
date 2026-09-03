// VisibilityViewModelTests
//
// BDD-named tests for the "Make Public" view model (work-consolidation.md G3).
// Visibility has no dedicated endpoint — it toggles through the resource's
// partial-update method — so the quartet is expressed against the document /
// list update stubs:
//   - happy: toggling on/off calls the matching update with only `isPublic`
//     set and adopts the server's returned value (document + list halves).
//   - invalid input: toggling to the current value is a no-op (no service call).
//   - upstream failure: a failing update rolls the optimistic flip back and
//     surfaces the error (required optimistic-UI rollback).
//   - boundary: the list half maps the returned `Visibility` enum back to the
//     public flag.
//
// The view models are `@MainActor`; the stubs are `actor`s, so recorded-call
// assertions `await` the stub.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class VisibilityViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(
        target: ShareTarget,
        isPublic: Bool
    ) -> (VisibilityViewModel, StubDocumentsService, StubListsService) {
        let documents = StubDocumentsService()
        let lists = StubListsService()
        let vm = VisibilityViewModel(target: target, documents: documents, lists: lists, isPublic: isPublic)
        return (vm, documents, lists)
    }

    private func document(id: String = "D1", isPublic: Bool) -> Document {
        Document(id: id, title: "Doc", updatedAt: Date(timeIntervalSince1970: 1_700_000_000), isPublic: isPublic)
    }

    // MARK: - Happy path (document half)

    func test_givenPrivateDocument_whenTurningPublic_thenCallsUpdateAndAdoptsServerValue() async {
        let (vm, documents, _) = makeViewModel(target: .document(id: "D1"), isPublic: false)
        await documents.enqueueUpdate(success: document(isPublic: true))

        await vm.setPublic(true)

        XCTAssertTrue(vm.isPublic)
        XCTAssertNil(vm.error)
        let recorded = await documents.recorded
        XCTAssertEqual(recorded, [.init(kind: .update(id: "D1", title: nil, body: nil, folderId: nil, isPublic: true))],
                       "Only the isPublic field is sent; the rest stay nil")
    }

    func test_givenPublicDocument_whenTurningPrivate_thenCallsUpdateWithFalse() async {
        let (vm, documents, _) = makeViewModel(target: .document(id: "D1"), isPublic: true)
        await documents.enqueueUpdate(success: document(isPublic: false))

        await vm.setPublic(false)

        XCTAssertFalse(vm.isPublic)
        let recorded = await documents.recorded
        XCTAssertEqual(recorded, [.init(kind: .update(id: "D1", title: nil, body: nil, folderId: nil, isPublic: false))])
    }

    // MARK: - Happy path (list half) + Visibility enum boundary

    func test_givenPrivateList_whenTurningPublic_thenMapsVisibilityEnumToFlag() async {
        let (vm, _, lists) = makeViewModel(target: .list(id: "L7"), isPublic: false)
        await lists.enqueueUpdate(success: ListsFixtures.ownedList(id: "L7", visibility: .public))

        await vm.setPublic(true)

        XCTAssertTrue(vm.isPublic, "A returned .public visibility maps to isPublic == true")
        XCTAssertNil(vm.error)
        let recorded = await lists.recorded
        XCTAssertEqual(recorded, [.init(kind: .update(listId: "L7", title: nil, description: nil, isPublic: true, parentId: nil))])
    }

    // MARK: - Invalid input (no-op)

    func test_givenAlreadyPublic_whenTurningPublic_thenNoOpAndCallsNoService() async {
        let (vm, documents, _) = makeViewModel(target: .document(id: "D1"), isPublic: true)

        await vm.setPublic(true)

        XCTAssertTrue(vm.isPublic)
        let recorded = await documents.recorded
        XCTAssertTrue(recorded.isEmpty, "Toggling to the current value must not reach the service")
    }

    // MARK: - Upstream API failure (rollback)

    func test_givenUpdateFails_whenTogglingDocument_thenRollsBackAndSurfacesError() async {
        let (vm, documents, _) = makeViewModel(target: .document(id: "D1"), isPublic: false)
        await documents.enqueueUpdate(failure: TestError.upstream("boom"))

        await vm.setPublic(true)

        XCTAssertFalse(vm.isPublic, "A failed toggle must roll back to the prior value")
        XCTAssertEqual(vm.error as? TestError, .upstream("boom"))
    }

    func test_givenUpdateFails_whenTogglingList_thenRollsBack() async {
        let (vm, _, lists) = makeViewModel(target: .list(id: "L7"), isPublic: true)
        await lists.enqueueUpdate(failure: TestError.upstream("nope"))

        await vm.setPublic(false)

        XCTAssertTrue(vm.isPublic, "A failed toggle must roll back to the prior value")
        XCTAssertEqual(vm.error as? TestError, .upstream("nope"))
    }
}
