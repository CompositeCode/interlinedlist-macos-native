// InvitesViewModelTests
//
// BDD-named tests for the "Invite by email" view model (work-consolidation.md
// G3). Covers the required quartet plus the pattern-specific additions:
//   - happy: load populates pending invites; a valid send forwards email /
//     role / expiry, captures the claim url, clears the field, and re-fetches
//     the authoritative list.
//   - invalid input: a blank / malformed email is rejected before the service
//     is called (asserted on the recorded-call log).
//   - upstream failure: a failing load surfaces the error; a failing revoke
//     rolls the optimistic prune back (required optimistic-UI rollback).
//   - empty / boundary: an empty invites response reports "loaded, none".
//   - subscriber gate: `subscriberRequired` on send raises the upsell, not
//     `error`, and adds no invite.
//   - both targets: the list and document halves dispatch to the matching
//     service methods.
//
// The view model is `@MainActor`; the stub is an `actor`, so recorded-call
// assertions `await` the stub.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class InvitesViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(target: ShareTarget = .document(id: "D1")) -> (InvitesViewModel, StubSharingService) {
        let service = StubSharingService()
        let vm = InvitesViewModel(service: service, target: target)
        return (vm, service)
    }

    private func invite(_ token: String, email: String = "a@example.com", role: ShareRole = .watcher, accepted: Bool = false) -> ShareInvite {
        ShareInvite(token: token, email: email, role: role, expiresAt: nil, accepted: accepted, createdAt: nil)
    }

    private func sent(_ email: String = "a@example.com", role: ShareRole = .watcher) -> SentInvite {
        SentInvite(email: email, role: role, expiresAt: nil, url: URL(string: "https://interlinedlist.com/invite/xyz"))
    }

    // MARK: - Happy path

    func test_givenInvites_whenLoading_thenPublishesPendingInvites() async {
        let (vm, service) = makeViewModel()
        await service.enqueueInvites(success: [invite("t1"), invite("t2", accepted: true)])

        await vm.load()

        XCTAssertEqual(vm.invites.map(\.token), ["t1", "t2"])
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .documentInvites(documentId: "D1"))])
    }

    func test_givenValidEmail_whenSending_thenForwardsFieldsCapturesURLAndRefreshes() async {
        let (vm, service) = makeViewModel()
        vm.newEmail = "  invitee@example.com "
        vm.newRole = .collaborator
        await service.enqueueCreateInvite(success: sent("invitee@example.com", role: .collaborator))
        await service.enqueueInvites(success: [invite("t9", email: "invitee@example.com", role: .collaborator)])

        await vm.send()

        XCTAssertEqual(vm.invites.map(\.token), ["t9"], "A successful send re-fetches the authoritative list")
        XCTAssertEqual(vm.newEmail, "", "A successful send clears the email field")
        XCTAssertEqual(vm.lastSentURL?.absoluteString, "https://interlinedlist.com/invite/xyz")
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [
            .init(kind: .createDocumentInvite(documentId: "D1", email: "invitee@example.com", role: .collaborator, expiresAt: nil)),
            .init(kind: .documentInvites(documentId: "D1"))
        ], "Send trims the email, forwards role, then re-fetches")
    }

    // MARK: - Invalid input (rejected before the service)

    func test_givenBlankEmail_whenSending_thenRejectsBeforeServiceCall() async {
        let (vm, service) = makeViewModel()
        vm.newEmail = "   "

        await vm.send()

        XCTAssertEqual(vm.error as? InvitesError, .invalidEmail)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "A blank email must not reach the service")
    }

    func test_givenMalformedEmail_whenSending_thenRejectsBeforeServiceCall() async {
        let (vm, service) = makeViewModel()
        vm.newEmail = "not-an-email"

        await vm.send()

        XCTAssertEqual(vm.error as? InvitesError, .invalidEmail)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "A malformed email must not reach the service")
    }

    // MARK: - Upstream API failure

    func test_givenUpstreamFailure_whenLoading_thenSurfacesErrorAndMarksLoaded() async {
        let (vm, service) = makeViewModel()
        await service.enqueueInvites(failure: TestError.upstream("net"))

        await vm.load()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertTrue(vm.invites.isEmpty)
    }

    func test_givenRevokeFails_whenRevoking_thenRestoresSnapshotAndSurfacesError() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(invites: [invite("keep"), invite("drop")])
        await service.enqueueRevokeInvite(failure: TestError.upstream("boom"))

        await vm.revoke(token: "drop")

        XCTAssertEqual(vm.invites.map(\.token), ["keep", "drop"], "Optimistic prune must roll back on failure")
        XCTAssertEqual(vm.error as? TestError, .upstream("boom"))
    }

    func test_givenServerReportsNotRevoked_whenRevoking_thenRestoresSnapshot() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(invites: [invite("keep"), invite("drop")])
        await service.enqueueRevokeInvite(success: false)

        await vm.revoke(token: "drop")

        XCTAssertEqual(vm.invites.map(\.token), ["keep", "drop"], "A false 'revoked' flag must restore the invite")
        XCTAssertNil(vm.error)
    }

    func test_givenRevokeSucceeds_whenRevoking_thenInviteRemovedAndRecorded() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(invites: [invite("keep"), invite("drop")])
        await service.enqueueRevokeInvite(success: true)

        await vm.revoke(token: "drop")

        XCTAssertEqual(vm.invites.map(\.token), ["keep"])
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .revokeDocumentInvite(documentId: "D1", token: "drop"))])
    }

    // MARK: - Empty / boundary

    func test_givenEmptyResponse_whenLoading_thenReportsLoadedWithNoInvites() async {
        let (vm, service) = makeViewModel()
        await service.enqueueInvites(success: [])

        await vm.load()

        XCTAssertTrue(vm.invites.isEmpty)
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    // MARK: - Subscriber gate

    func test_givenFreeAccount_whenSending_thenRaisesUpsellAndAddsNoInvite() async {
        let (vm, service) = makeViewModel()
        vm.newEmail = "invitee@example.com"
        await service.enqueueCreateInvite(failure: SharingError.subscriberRequired)

        await vm.send()

        XCTAssertTrue(vm.showSubscriberUpsell, "A gated send raises the upsell")
        XCTAssertNil(vm.error, "subscriberRequired must not surface as a generic error")
        XCTAssertTrue(vm.invites.isEmpty)
    }

    // MARK: - Target dispatch (lists half)

    func test_givenListTarget_whenLoading_thenCallsListInvitesEndpoint() async {
        let (vm, service) = makeViewModel(target: .list(id: "L7"))
        await service.enqueueInvites(success: [invite("t1")])

        await vm.load()

        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .listInvites(listId: "L7"))])
    }

    func test_givenListTarget_whenSending_thenCallsCreateListInvite() async {
        let (vm, service) = makeViewModel(target: .list(id: "L7"))
        vm.newEmail = "invitee@example.com"
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        vm.newExpiresAt = expiry
        await service.enqueueCreateInvite(success: sent())
        await service.enqueueInvites(success: [invite("t1")])

        await vm.send()

        let recorded = await service.recorded
        XCTAssertEqual(recorded.first, .init(kind: .createListInvite(listId: "L7", email: "invitee@example.com", role: .watcher, expiresAt: expiry)),
                       "The list half forwards the expiry to createListInvite")
    }
}
