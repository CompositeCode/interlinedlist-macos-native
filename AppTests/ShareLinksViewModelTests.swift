// ShareLinksViewModelTests
//
// BDD-named tests for the Share Links view model (work-consolidation.md G3). Covers
// the required quartet plus the pattern-specific additions:
//   - happy: load populates active links; create prepends the server link.
//   - invalid input: the subscriber-gate rejects create *before* the HTTP
//     round-trip — asserted via the upsell flag and (per the gate design)
//     the recorded-call log; a whitespace-only nothing case is covered by
//     the empty/boundary member.
//   - upstream failure: a failing load surfaces the error; a failing revoke
//     rolls the optimistic prune back (required optimistic-UI rollback).
//   - empty / boundary: an empty links response reports "loaded, none".
//   - subscriber gate: `subscriberRequired` raises the upsell, not `error`,
//     and does not add a link.
//   - both targets: the list and document halves dispatch to the matching
//     service methods (asserted on the recorded-call log).
//
// The view model is `@MainActor`; the stub is an `actor`, so recorded-call
// assertions `await` the stub.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ShareLinksViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(target: ShareTarget = .list(id: "L1")) -> (ShareLinksViewModel, StubSharingService) {
        let service = StubSharingService()
        let vm = ShareLinksViewModel(service: service, target: target)
        return (vm, service)
    }

    private func link(_ token: String, role: ShareRole = .watcher, revokedAt: Date? = nil) -> ShareLink {
        ShareLink(
            token: token,
            url: URL(string: "https://interlinedlist.com/lists/shared/\(token)"),
            role: role,
            expiresAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            revokedAt: revokedAt
        )
    }

    // MARK: - Happy path

    func test_givenActiveLinks_whenLoading_thenPublishesOnlyNonRevoked() async {
        let (vm, service) = makeViewModel()
        await service.enqueueLinks(success: [link("t1"), link("t2", revokedAt: Date()), link("t3")])

        await vm.load()

        XCTAssertEqual(vm.links.map(\.token), ["t1", "t3"], "Revoked links must be filtered out")
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .listLinks(listId: "L1"))])
    }

    func test_givenSubscriber_whenCreating_thenPrependsServerReturnedLink() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(links: [link("old")])
        await service.enqueueCreate(success: link("new", role: .collaborator))
        vm.newRole = .collaborator

        let created = await vm.create()

        XCTAssertEqual(created?.token, "new")
        XCTAssertEqual(vm.links.map(\.token), ["new", "old"], "New link is prepended")
        XCTAssertFalse(vm.showSubscriberUpsell)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .createListLink(listId: "L1", role: .collaborator, expiresAt: nil))])
    }

    // MARK: - Invalid input (subscriber gate rejects before surfacing as error)

    func test_givenFreeAccount_whenCreating_thenRaisesUpsellAndDoesNotAddLink() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(links: [link("only")])
        // The domain service throws `subscriberRequired` before any HTTP.
        await service.enqueueCreate(failure: SharingError.subscriberRequired)

        let created = await vm.create()

        XCTAssertNil(created)
        XCTAssertTrue(vm.showSubscriberUpsell, "Free-tier create must raise the upsell, not an error")
        XCTAssertNil(vm.error, "subscriberRequired must not surface as a generic error")
        XCTAssertEqual(vm.links.map(\.token), ["only"], "No link is added on a gated create")
    }

    func test_givenUpsellShown_whenDismissed_thenUpsellCleared() async {
        let (vm, service) = makeViewModel()
        await service.enqueueCreate(failure: SharingError.subscriberRequired)
        _ = await vm.create()
        XCTAssertTrue(vm.showSubscriberUpsell)

        vm.dismissUpsell()

        XCTAssertFalse(vm.showSubscriberUpsell)
    }

    // MARK: - Upstream API failure

    func test_givenUpstreamFailure_whenLoading_thenSurfacesErrorAndMarksLoaded() async {
        let (vm, service) = makeViewModel()
        await service.enqueueLinks(failure: TestError.upstream("net"))

        await vm.load()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertTrue(vm.links.isEmpty)
    }

    // MARK: - Optimistic revoke rollback (required)

    func test_givenRevokeFails_whenRevoking_thenRestoresSnapshotAndSurfacesError() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(links: [link("keep"), link("drop")])
        await service.enqueueRevoke(failure: TestError.upstream("boom"))

        await vm.revoke(token: "drop")

        XCTAssertEqual(vm.links.map(\.token), ["keep", "drop"], "Optimistic prune must roll back on failure")
        XCTAssertEqual(vm.error as? TestError, .upstream("boom"))
    }

    func test_givenRevokeSucceeds_whenRevoking_thenLinkRemovedAndNoError() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(links: [link("keep"), link("drop")])
        await service.enqueueRevoke(success: true)

        await vm.revoke(token: "drop")

        XCTAssertEqual(vm.links.map(\.token), ["keep"])
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .revokeListLink(listId: "L1", token: "drop"))])
    }

    func test_givenServerReportsNotRevoked_whenRevoking_thenRestoresSnapshot() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(links: [link("keep"), link("drop")])
        // Server returns revoked == false → the link is still live.
        await service.enqueueRevoke(success: false)

        await vm.revoke(token: "drop")

        XCTAssertEqual(vm.links.map(\.token), ["keep", "drop"], "A false 'revoked' flag must restore the link")
        XCTAssertNil(vm.error)
    }

    // MARK: - Empty / boundary

    func test_givenEmptyResponse_whenLoading_thenReportsLoadedWithNoLinks() async {
        let (vm, service) = makeViewModel()
        await service.enqueueLinks(success: [])

        await vm.load()

        XCTAssertTrue(vm.links.isEmpty)
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    // MARK: - Target dispatch (documents half)

    func test_givenDocumentTarget_whenCreating_thenCallsDocumentEndpoint() async {
        let (vm, service) = makeViewModel(target: .document(id: "D9"))
        await service.enqueueCreate(success: link("doc-link", role: .manager))
        vm.newRole = .manager

        _ = await vm.create()

        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .createDocumentLink(documentId: "D9", role: .manager, expiresAt: nil))])
        XCTAssertEqual(vm.links.map(\.token), ["doc-link"])
    }

    func test_givenDocumentTarget_whenLoading_thenCallsDocumentLinksEndpoint() async {
        let (vm, service) = makeViewModel(target: .document(id: "D9"))
        await service.enqueueLinks(success: [link("t1")])

        await vm.load()

        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .documentLinks(documentId: "D9"))])
    }

    // MARK: - Expiry threading

    func test_givenExpirySet_whenCreating_thenExpiryForwardedToService() async {
        let (vm, service) = makeViewModel()
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        vm.newExpiresAt = expiry
        await service.enqueueCreate(success: link("t1"))

        _ = await vm.create()

        let recorded = await service.recorded
        XCTAssertEqual(recorded, [.init(kind: .createListLink(listId: "L1", role: .watcher, expiresAt: expiry))])
    }
}
