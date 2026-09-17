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
        // A list resolve is followed by the shared-row read (G23), so assert
        // on the first call rather than the whole log.
        let recorded = await service.recorded
        XCTAssertEqual(recorded.first, .init(kind: .resolveList(token: "tok")))
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
        // No claim call was recorded — the guard skipped it. (A list resolve is
        // now followed by the G23 shared-row read, so filter to claims.)
        let recorded = await service.recorded
        XCTAssertFalse(recorded.contains(.init(kind: .claimList(token: "tok"))))
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

    // MARK: - Shared row data (work-consolidation.md G23 / issue #48)

    func test_givenListShare_whenResolving_thenAlsoReadsTheSharedRows() async {
        // Happy path: a read-only viewer must see the rows, not just the title.
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved())
        await service.enqueueSharedRows(success: ListsFixtures.rowsPage([
            ListsFixtures.row(id: "r1", fields: ["Title": .string("Dune")]),
            ListsFixtures.row(id: "r2", fields: ["Title": .string("Neuromancer")])
        ]))

        await vm.resolve()

        XCTAssertEqual(vm.rows.map(\.id), ["r1", "r2"])
        XCTAssertEqual(vm.columns, ["Title"])
        XCTAssertNil(vm.rowsError)
        XCTAssertTrue(vm.hasLoadedRowsOnce)
        let recorded = await service.recorded
        XCTAssertEqual(
            recorded.last,
            .init(kind: .sharedListRows(
                token: "tok",
                limit: ResolveShareViewModel.rowPageSize,
                offset: 0
            ))
        )
    }

    func test_givenDocumentShare_whenResolving_thenSkipsTheRowRead() async {
        // Invalid target: documents have no row-data route — the resolve call
        // returns their body directly — so no read may be attempted.
        let (vm, service) = makeViewModel(parsed: ParsedShare(kind: .document, token: "dtok"))
        await service.enqueueResolve(success: resolved(
            resource: .document(id: "D1", title: "Spec", isPublic: false)
        ))

        await vm.resolve()

        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertFalse(vm.hasLoadedRowsOnce)
        let recorded = await service.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenRowsReadFails_whenResolving_thenKeepsResolvedHeaderAndScopesError() async {
        // Upstream failure: the rows half failing must not hide the title and
        // role that resolved fine.
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved())
        await service.enqueueSharedRows(failure: TestError.upstream("rows-500"))

        await vm.resolve()

        XCTAssertEqual(vm.resolved?.resource?.title, "Roadmap")
        XCTAssertNil(vm.error, "The resolve succeeded; its error slot stays clear.")
        XCTAssertEqual(vm.rowsError as? TestError, .upstream("rows-500"))
        XCTAssertTrue(vm.rows.isEmpty)
    }

    func test_givenResolveFails_whenResolving_thenSkipsTheRowRead() async {
        // A dead token would fail both calls identically; spending the second
        // round-trip to learn the same 404 helps nobody.
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(failure: TestError.upstream("gone"))

        await vm.resolve()

        XCTAssertNil(vm.resolved)
        let recorded = await service.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenEmptySharedList_whenResolving_thenReportsLoadedWithNoRows() async {
        // Boundary: an empty shared list. `hasLoadedRowsOnce` lets the view
        // say "no rows yet" instead of leaving a blank gap.
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved())
        await service.enqueueSharedRows(success: ListsFixtures.rowsPage([]))

        await vm.resolve()

        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertTrue(vm.columns.isEmpty)
        XCTAssertTrue(vm.hasLoadedRowsOnce)
        XCTAssertNil(vm.rowsError)
    }

    func test_givenPriorRowsFailure_whenRetryingRows_thenPopulatesWithoutReResolving() async {
        // The view's rows-only "Try Again" path.
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved())
        await service.enqueueSharedRows(failure: TestError.upstream("boom"))
        await service.enqueueSharedRows(success: ListsFixtures.rowsPage([
            ListsFixtures.row(id: "r1", fields: ["Title": .string("Dune")])
        ]))
        await vm.resolve()

        await vm.loadRows()

        XCTAssertEqual(vm.rows.map(\.id), ["r1"])
        XCTAssertNil(vm.rowsError)
        let recorded = await service.recorded
        XCTAssertEqual(recorded.filter { $0.kind == .resolveList(token: "tok") }.count, 1)
    }

    func test_givenRowsWithDifferentColumns_whenResolving_thenColumnsAreUnionedAndSorted() async {
        // Boundary: a token-scoped read carries no schema, so the column order
        // is derived from the rows and must be deterministic.
        let (vm, service) = makeViewModel()
        await service.enqueueResolve(success: resolved())
        await service.enqueueSharedRows(success: ListsFixtures.rowsPage([
            ListsFixtures.row(id: "r1", fields: ["Year": .int(1965)]),
            ListsFixtures.row(id: "r2", fields: ["Title": .string("Dune")])
        ]))

        await vm.resolve()

        XCTAssertEqual(vm.columns, ["Title", "Year"])
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
