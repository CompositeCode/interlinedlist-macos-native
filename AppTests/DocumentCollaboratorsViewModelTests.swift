// DocumentCollaboratorsViewModelTests
//
// BDD-named tests for the document "Access & Permissions" view model
// (work-consolidation.md G3). Covers the required quartet plus the
// pattern-specific additions:
//   - happy: load populates the access list; search populates candidates;
//     add inserts the new row, forwards role + notify, and clears the search.
//   - invalid input: a blank search query is rejected before the service is
//     called (asserted on the recorded-call log); a duplicate add is a no-op.
//   - upstream failure: a failing load surfaces the error; a failing remove /
//     set-role rolls the optimistic mutation back (required optimistic-UI
//     rollback).
//   - empty / boundary: an empty collaborators response reports "loaded, none".
//   - subscriber gate: `subscriberRequired` on add / set-role raises the
//     upsell, not `error`, and rolls the optimistic mutation back.
//
// The view model is `@MainActor`; the stub is an `actor`, so recorded-call
// assertions `await` the stub.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DocumentCollaboratorsViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(documentId: String = "D1") -> (DocumentCollaboratorsViewModel, StubSharingService) {
        let service = StubSharingService()
        let vm = DocumentCollaboratorsViewModel(service: service, documentId: documentId)
        return (vm, service)
    }

    private func collaborator(_ userId: String, role: ShareRole = .watcher, name: String? = nil) -> Collaborator {
        Collaborator(userId: userId, role: role, username: name ?? userId, displayName: name, avatar: nil, createdAt: nil)
    }

    private func candidate(_ id: String, name: String? = nil) -> CollaboratorCandidate {
        CollaboratorCandidate(id: id, username: name ?? id, displayName: name, email: "\(id)@example.com", avatar: nil)
    }

    // MARK: - Happy path

    func test_givenCollaborators_whenLoading_thenPublishesAccessList() async {
        let (vm, service) = makeViewModel()
        await service.enqueueCollaborators(success: [collaborator("u1"), collaborator("u2", role: .manager)])

        await vm.load()

        XCTAssertEqual(vm.collaborators.map(\.userId), ["u1", "u2"])
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .documentCollaborators(documentId: "D1"))])
    }

    func test_givenQuery_whenSearching_thenPublishesCandidates() async {
        let (vm, service) = makeViewModel()
        vm.searchQuery = "  adron "
        await service.enqueueCandidates(success: [candidate("u9", name: "Adron")])

        await vm.search()

        XCTAssertEqual(vm.searchResults.map(\.id), ["u9"])
        let recorded = await service.recorded
        // The query is trimmed before it reaches the service.
        XCTAssertEqual(recorded, [.init(kind: .searchCollaborators(documentId: "D1", query: "adron"))])
    }

    func test_givenCandidateAndRole_whenAdding_thenInsertsForwardsNotifyAndClearsSearch() async {
        let (vm, service) = makeViewModel()
        vm.searchQuery = "adron"
        vm.newRole = .collaborator
        vm.notify = false
        await service.enqueueAddCollaboratorSuccess()

        await vm.add(candidate: candidate("u9", name: "Adron"))

        XCTAssertEqual(vm.collaborators.map(\.userId), ["u9"])
        XCTAssertEqual(vm.collaborators.first?.role, .collaborator, "The new row adopts the selected role for new users")
        XCTAssertTrue(vm.searchResults.isEmpty, "A successful add clears the search results")
        XCTAssertEqual(vm.searchQuery, "", "A successful add clears the search text")
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .addCollaborator(documentId: "D1", userId: "u9", role: .collaborator, notify: false))])
    }

    func test_givenCollaborator_whenChangingRole_thenRewritesRowAndDoesNotRenotify() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(collaborators: [collaborator("u1", role: .watcher)])
        await service.enqueueSetRoleSuccess()

        await vm.setRole(userId: "u1", role: .manager)

        XCTAssertEqual(vm.collaborators.first?.role, .manager)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .setCollaboratorRole(documentId: "D1", userId: "u1", role: .manager, notify: false))],
                       "A role change must not re-email the collaborator")
    }

    // MARK: - Invalid input (rejected before the service)

    func test_givenBlankQuery_whenSearching_thenClearsResultsAndCallsNoService() async {
        let (vm, service) = makeViewModel()
        await service.enqueueCandidates(success: [candidate("should-not-be-used")])
        vm.searchQuery = "   "

        await vm.search()

        XCTAssertTrue(vm.searchResults.isEmpty)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "A blank query must not reach the service")
    }

    func test_givenExistingCollaborator_whenAddingSameUser_thenNoOpAndCallsNoService() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(collaborators: [collaborator("u1")])

        await vm.add(candidate: candidate("u1"))

        XCTAssertEqual(vm.collaborators.map(\.userId), ["u1"], "A duplicate add must not duplicate the row")
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "Adding an existing collaborator must not reach the service")
    }

    // MARK: - Upstream API failure

    func test_givenUpstreamFailure_whenLoading_thenSurfacesErrorAndMarksLoaded() async {
        let (vm, service) = makeViewModel()
        await service.enqueueCollaborators(failure: TestError.upstream("net"))

        await vm.load()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertTrue(vm.collaborators.isEmpty)
    }

    func test_givenRemoveFails_whenRemoving_thenRestoresSnapshotAndSurfacesError() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(collaborators: [collaborator("keep"), collaborator("drop")])
        await service.enqueueRemoveCollaborator(failure: TestError.upstream("boom"))

        await vm.remove(userId: "drop")

        XCTAssertEqual(vm.collaborators.map(\.userId), ["keep", "drop"], "Optimistic prune must roll back on failure")
        XCTAssertEqual(vm.error as? TestError, .upstream("boom"))
    }

    func test_givenServerReportsNotRemoved_whenRemoving_thenRestoresSnapshot() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(collaborators: [collaborator("keep"), collaborator("drop")])
        await service.enqueueRemoveCollaborator(success: false)

        await vm.remove(userId: "drop")

        XCTAssertEqual(vm.collaborators.map(\.userId), ["keep", "drop"], "A false 'removed' flag must restore the row")
        XCTAssertNil(vm.error)
    }

    func test_givenRemoveSucceeds_whenRemoving_thenRowPrunedAndRecorded() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(collaborators: [collaborator("keep"), collaborator("drop")])
        await service.enqueueRemoveCollaborator(success: true)

        await vm.remove(userId: "drop")

        XCTAssertEqual(vm.collaborators.map(\.userId), ["keep"])
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .removeCollaborator(documentId: "D1", userId: "drop"))])
    }

    func test_givenSetRoleFails_whenChangingRole_thenRestoresPriorRole() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(collaborators: [collaborator("u1", role: .watcher)])
        await service.enqueueSetRole(failure: TestError.upstream("nope"))

        await vm.setRole(userId: "u1", role: .manager)

        XCTAssertEqual(vm.collaborators.first?.role, .watcher, "A failed role change must roll back")
        XCTAssertEqual(vm.error as? TestError, .upstream("nope"))
    }

    // MARK: - Empty / boundary

    func test_givenEmptyResponse_whenLoading_thenReportsLoadedWithNoCollaborators() async {
        let (vm, service) = makeViewModel()
        await service.enqueueCollaborators(success: [])

        await vm.load()

        XCTAssertTrue(vm.collaborators.isEmpty)
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    // MARK: - Subscriber gate

    func test_givenFreeAccount_whenAdding_thenRaisesUpsellAndRollsBack() async {
        let (vm, service) = makeViewModel()
        vm.newRole = .collaborator
        await service.enqueueAddCollaborator(failure: SharingError.subscriberRequired)

        await vm.add(candidate: candidate("u9"))

        XCTAssertTrue(vm.showSubscriberUpsell, "A gated add raises the upsell")
        XCTAssertNil(vm.error, "subscriberRequired must not surface as a generic error")
        XCTAssertTrue(vm.collaborators.isEmpty, "The optimistic row must roll back on a gated add")
    }

    func test_givenFreeAccount_whenChangingRole_thenRaisesUpsellAndRollsBack() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(collaborators: [collaborator("u1", role: .watcher)])
        await service.enqueueSetRole(failure: SharingError.subscriberRequired)

        await vm.setRole(userId: "u1", role: .manager)

        XCTAssertTrue(vm.showSubscriberUpsell)
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.collaborators.first?.role, .watcher, "The optimistic role change must roll back")
    }
}
