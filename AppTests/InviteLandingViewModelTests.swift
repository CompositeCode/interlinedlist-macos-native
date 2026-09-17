// InviteLandingViewModelTests
//
// BDD-named tests for the email-invite landing (work-consolidation.md G23 /
// issue #48).
//
// The central contract is negative: this view model must never offer a native
// accept. `POST /api/lists/invite/{token}` is session-only in the live spec, so
// the only path forward is the browser hand-off — and the guidance copy has to
// say so for every combination of flags the landing payload returns.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class InviteLandingViewModelTests: XCTestCase {

    private let webBase = URL(string: "https://interlinedlist.com")!

    private func makeViewModel(
        parsed: ParsedShare = ParsedShare(kind: .list, token: "tok", mode: .invite)
    ) -> (InviteLandingViewModel, StubSharingService) {
        let service = StubSharingService()
        let vm = InviteLandingViewModel(service: service, parsed: parsed, webBaseURL: webBase)
        return (vm, service)
    }

    // MARK: - resolve

    func test_givenClaimableInvite_whenResolving_thenPopulatesRoleAndTitle() async {
        let (vm, service) = makeViewModel()
        await service.enqueueResolveInvite(success: ResolvedListInvite(
            role: .collaborator,
            needsAuth: false,
            canClaim: true,
            wrongAccount: false,
            accepted: false,
            resourceTitle: "Q3 Planning"
        ))

        await vm.resolve()

        XCTAssertEqual(vm.invite?.role, .collaborator)
        XCTAssertEqual(vm.invite?.resourceTitle, "Q3 Planning")
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertEqual(recorded.first?.kind, .resolveListInvite(token: "tok"))
    }

    func test_givenDocumentInvite_whenResolving_thenReportsUnsupportedWithoutCallingService() async {
        // Invalid input for this client: issue #48 scopes the invite work to
        // Lists, so a document invite gets the browser hand-off rather than a
        // dead deep link — and no service call is made.
        let (vm, service) = makeViewModel(
            parsed: ParsedShare(kind: .document, token: "dtok", mode: .invite)
        )

        await vm.resolve()

        XCTAssertTrue(vm.isUnsupportedResource)
        XCTAssertNil(vm.invite)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenExpiredToken_whenResolving_thenSurfacesError() async {
        // Upstream failure: unknown / expired / revoked are one 404.
        let (vm, service) = makeViewModel()
        await service.enqueueResolveInvite(failure: TestError.upstream("not-found"))

        await vm.resolve()

        XCTAssertNil(vm.invite)
        XCTAssertEqual(vm.error as? TestError, .upstream("not-found"))
    }

    func test_givenAnonymousResolveWithMinimalFlags_whenResolving_thenPromptsSignIn() async {
        // Boundary: the payload can arrive with almost nothing set.
        let (vm, service) = makeViewModel()
        await service.enqueueResolveInvite(success: ResolvedListInvite(
            role: .watcher,
            needsAuth: true,
            canClaim: false,
            wrongAccount: false,
            accepted: false,
            resourceTitle: nil
        ))

        await vm.resolve()

        XCTAssertNil(vm.invite?.resourceTitle)
        XCTAssertEqual(vm.guidance, "Sign in on the web to accept this invite.")
    }

    // MARK: - guidance precedence

    func test_givenAcceptedInvite_whenReadingGuidance_thenSaysAlreadyAccepted() async {
        // Most specific first: an accepted invite is a dead end regardless of
        // who is signed in.
        let (vm, service) = makeViewModel()
        await service.enqueueResolveInvite(success: ResolvedListInvite(
            role: .collaborator,
            needsAuth: true,
            canClaim: true,
            wrongAccount: true,
            accepted: true,
            resourceTitle: "Q3"
        ))

        await vm.resolve()

        XCTAssertEqual(vm.guidance, "This invite has already been accepted.")
    }

    func test_givenWrongAccount_whenReadingGuidance_thenOutranksSignInPrompt() async {
        let (vm, service) = makeViewModel()
        await service.enqueueResolveInvite(success: ResolvedListInvite(
            role: .collaborator,
            needsAuth: true,
            canClaim: false,
            wrongAccount: true,
            accepted: false,
            resourceTitle: "Q3"
        ))

        await vm.resolve()

        XCTAssertTrue(vm.guidance.contains("different email"))
    }

    func test_givenClaimableInvite_whenReadingGuidance_thenSaysAcceptHappensInBrowser() async {
        // The negative contract, in the user-facing copy.
        let (vm, service) = makeViewModel()
        await service.enqueueResolveInvite(success: ResolvedListInvite(
            role: .collaborator,
            needsAuth: false,
            canClaim: true,
            wrongAccount: false,
            accepted: false,
            resourceTitle: "Q3"
        ))

        await vm.resolve()

        XCTAssertTrue(vm.guidance.contains("browser"))
    }

    func test_givenNoInviteResolved_whenReadingGuidance_thenIsEmpty() {
        // Boundary: nothing resolved yet, so there is nothing to advise.
        let (vm, _) = makeViewModel()

        XCTAssertEqual(vm.guidance, "")
    }

    // MARK: - browser hand-off

    func test_givenListInvite_whenBuildingAcceptURL_thenPointsAtTheWebInvitePath() {
        let (vm, _) = makeViewModel()

        XCTAssertEqual(
            vm.acceptInBrowserURL?.absoluteString,
            "https://interlinedlist.com/lists/invite/tok"
        )
    }

    func test_givenDocumentInvite_whenBuildingAcceptURL_thenUsesTheDocumentPath() {
        // Even the unsupported case gets a working hand-off.
        let (vm, _) = makeViewModel(
            parsed: ParsedShare(kind: .document, token: "dtok", mode: .invite)
        )

        XCTAssertEqual(
            vm.acceptInBrowserURL?.absoluteString,
            "https://interlinedlist.com/documents/invite/dtok"
        )
    }
}
