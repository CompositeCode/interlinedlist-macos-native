// ResolveShareViewModelTests
//
// BDD-named tests for the shared-resource landing view model (work-consolidation.md
// G3). Covers the required quartet plus the ownership-gating rule:
//   - happy: resolve populates the resource + role; claim (signed in,
//     claimable) records the authoritative `ShareClaim`.
//   - invalid input: `claimAccess()` on a non-claimable / signed-out share
//     is a guarded no-op — asserts the claim service was never called.
//   - upstream failure: a failing resolve surfaces the error and leaves
//     `resolved` nil; a failing claim surfaces the error without flipping
//     `didClaim`.
//   - empty / boundary: a resolve with no `resource` still populates role
//     and reports a title-less preview.
//   - ownership gating: a claimable share with a `nil` current user hides
//     the claim button (`canOfferClaim == false`) and prompts sign-in
//     (`needsSignIn == true`) — never enabled-but-broken.
//   - target dispatch: list vs document resolves/claims hit the matching
//     service methods.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ResolveShareViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(
        parsed: ParsedShare = ParsedShare(kind: .list, token: "tok"),
        currentUserID: String? = "U1"
    ) -> (ResolveShareViewModel, StubSharingService) {
        let service = StubSharingService()
        let vm = ResolveShareViewModel(service: service, parsed: parsed, currentUserID: currentUserID)
        return (vm, service)
    }

    private func resolved(
        role: ShareRole = .collaborator,
        canClaim: Bool = true,
        needsAuth: Bool = false,
        resource: ResolvedShare.Resource? = .list(id: "L1", title: "Roadmap", description: nil, isPublic: false)
    ) -> ResolvedShare {
        ResolvedShare(role: role, canClaim: canClaim, needsAuth: needsAuth, resource: resource)
    }

    // MARK: - Happy path

    func test_givenListToken_whenResolving_thenPublishesResourceAndRole() async {
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved())

        await vm.resolve()

        XCTAssertEqual(vm.resolved?.resource?.title, "Roadmap")
        XCTAssertEqual(vm.resolved?.role, .collaborator)
        XCTAssertTrue(vm.canOfferClaim, "Signed-in + claimable → claim offered")
        XCTAssertFalse(vm.needsSignIn)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .resolveList(token: "tok"))])
    }

    func test_givenClaimableShare_whenClaiming_thenRecordsAuthoritativeClaim() async {
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved())
        await service.enqueueClaim(success: ShareClaim(resourceId: "L1", role: .collaborator))
        await vm.resolve()

        await vm.claimAccess()

        XCTAssertTrue(vm.didClaim)
        XCTAssertEqual(vm.claim?.resourceId, "L1")
        XCTAssertEqual(vm.claim?.role, .collaborator)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded.last, .init(kind: .claimList(token: "tok")))
    }

    // MARK: - Invalid input (guarded claim → no service call)

    func test_givenNonClaimableShare_whenClaiming_thenNoServiceCallAndNoClaim() async {
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved(canClaim: false))
        await vm.resolve()

        await vm.claimAccess()

        XCTAssertFalse(vm.didClaim)
        XCTAssertNil(vm.claim)
        // Only the resolve call was recorded — the guard skipped the claim.
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .resolveList(token: "tok"))])
    }

    // MARK: - Upstream API failure

    func test_givenUpstreamFailure_whenResolving_thenSurfacesErrorAndLeavesResolvedNil() async {
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(failure: TestError.upstream("gone"))

        await vm.resolve()

        XCTAssertNil(vm.resolved)
        XCTAssertEqual(vm.error as? TestError, .upstream("gone"))
    }

    func test_givenClaimFails_whenClaiming_thenSurfacesErrorAndDidClaimStaysFalse() async {
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved())
        await service.enqueueClaim(failure: TestError.upstream("denied"))
        await vm.resolve()

        await vm.claimAccess()

        XCTAssertFalse(vm.didClaim)
        XCTAssertEqual(vm.error as? TestError, .upstream("denied"))
    }

    // MARK: - Empty / boundary

    func test_givenResolveWithNoResource_whenResolving_thenRolePopulatedAndTitleNil() async {
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved(resource: nil))

        await vm.resolve()

        XCTAssertNotNil(vm.resolved)
        XCTAssertNil(vm.resolved?.resource)
        XCTAssertEqual(vm.resolved?.role, .collaborator)
    }

    // MARK: - Ownership gating (nil user hides claim, prompts sign-in)

    func test_givenClaimableShareButNoCurrentUser_whenResolving_thenClaimHiddenAndSignInPrompted() async {
        let (vm, service) = makeViewModel(currentUserID: nil)
        await service.enqueueResolve(success: resolved(canClaim: true))

        await vm.resolve()

        XCTAssertFalse(vm.canOfferClaim, "Unknown user must hide the claim action")
        XCTAssertTrue(vm.needsSignIn, "A claimable share with no user prompts sign-in")
    }

    func test_givenNeedsAuthShare_whenResolving_thenSignInPrompted() async {
        let (vm, service) = makeViewModel(currentUserID: "U1")
        await service.enqueueResolve(success: resolved(canClaim: false, needsAuth: true))

        await vm.resolve()

        XCTAssertTrue(vm.needsSignIn)
        XCTAssertFalse(vm.canOfferClaim)
    }

    func test_givenSignInResolvesLater_whenCurrentUserUpdated_thenClaimBecomesOfferable() async {
        let (vm, service) = makeViewModel(currentUserID: nil)
        await service.enqueueResolve(success: resolved(canClaim: true))
        await vm.resolve()
        XCTAssertFalse(vm.canOfferClaim)

        vm.updateCurrentUser(id: "U2")

        XCTAssertTrue(vm.canOfferClaim, "Once a user resolves, a claimable share becomes offerable")
        XCTAssertFalse(vm.needsSignIn)
    }

    // MARK: - Target dispatch (documents half)

    func test_givenDocumentToken_whenResolving_thenCallsDocumentEndpoint() async {
        let (vm, service) = makeViewModel(parsed: ParsedShare(kind: .document, token: "dtok"))
        await service.enqueueResolve(success: resolved(
            resource: .document(id: "D1", title: "Spec", isPublic: false)
        ))

        await vm.resolve()

        XCTAssertEqual(vm.resolved?.resource?.title, "Spec")
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .resolveDocument(token: "dtok"))])
    }

    func test_givenDocumentToken_whenClaiming_thenCallsDocumentClaimEndpoint() async {
        let (vm, service) = makeViewModel(parsed: ParsedShare(kind: .document, token: "dtok"))
        await service.enqueueResolve(success: resolved(
            resource: .document(id: "D1", title: "Spec", isPublic: false)
        ))
        await service.enqueueClaim(success: ShareClaim(resourceId: "D1", role: .manager))
        await vm.resolve()

        await vm.claimAccess()

        XCTAssertTrue(vm.didClaim)
        XCTAssertEqual(vm.claim?.resourceId, "D1")
        let recorded = await service.recorded
        XCTAssertEqual(recorded.last, .init(kind: .claimDocument(token: "dtok")))
    }
}
