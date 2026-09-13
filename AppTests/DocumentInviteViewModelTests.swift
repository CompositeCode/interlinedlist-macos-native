// DocumentInviteViewModelTests
//
// BDD-named tests for the document invite landing (work-consolidation.md G24)
// and its URL parser.
//
// The most important assertions here are the negative ones: the landing
// resolves and *stops*. `POST /api/documents/invite/{token}` is session-cookie
// only upstream, so this app cannot claim an invite — the view model has no
// accept intent, and the parser must not mistake a share link for an invite.
//
// Stubbed `DocumentsServicing`; no networking, no SwiftUI rendering.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DocumentInviteViewModelTests: XCTestCase {

    private let webBase = URL(string: "https://interlinedlist.com")!

    private func makeViewModel(
        _ stub: StubDocumentsService,
        token: String = "xN3v9Qk"
    ) -> DocumentInviteViewModel {
        DocumentInviteViewModel(documents: stub, token: token, webBaseURL: webBase)
    }

    // MARK: - Happy path

    func test_givenResolvableInvite_whenResolving_thenShowsTitleRoleAndTheBrowserHandOff() async {
        let stub = StubDocumentsService()
        await stub.enqueueInvite(success: DocumentsFixtures.invite(
            token: "xN3v9Qk", role: "collaborator", resourceTitle: "Q3 Planning", canClaim: true
        ))
        let viewModel = makeViewModel(stub)

        await viewModel.resolve()

        XCTAssertEqual(viewModel.invite?.role, "collaborator")
        XCTAssertEqual(viewModel.displayTitle, "Q3 Planning")
        XCTAssertEqual(viewModel.nextStep, .acceptInBrowser)
        XCTAssertEqual(
            viewModel.acceptURL?.absoluteString,
            "https://interlinedlist.com/documents/invite/xN3v9Qk"
        )
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.map(\.kind), [.invite(token: "xN3v9Qk")])
    }

    func test_givenAnyResolvedInvite_whenInspectingTheViewModel_thenThereIsNoClaimPath() async {
        // The constraint, asserted as behaviour rather than left as a comment:
        // every branch ends at a browser hand-off. If someone later adds a
        // claim intent, `nextStep` gains a case and this test tells them why
        // that route cannot work from a Bearer client.
        let stub = StubDocumentsService()
        await stub.enqueueInvite(success: DocumentsFixtures.invite(canClaim: true))
        let viewModel = makeViewModel(stub)

        await viewModel.resolve()

        let steps: [DocumentInviteViewModel.NextStep] = [
            .alreadyAccepted, .signInInBrowser, .wrongAccount, .acceptInBrowser
        ]
        XCTAssertTrue(steps.contains(viewModel.nextStep!))
        XCTAssertNotNil(viewModel.acceptURL, "the hand-off is always available once resolved")
    }

    // MARK: - Branch selection

    func test_givenSignedOutInvite_whenResolved_thenAsksTheUserToSignInInTheBrowser() async {
        let stub = StubDocumentsService()
        await stub.enqueueInvite(success: DocumentsFixtures.invite(needsAuth: true, canClaim: false))
        let viewModel = makeViewModel(stub)

        await viewModel.resolve()

        XCTAssertEqual(viewModel.nextStep, .signInInBrowser)
    }

    func test_givenMismatchedAccount_whenResolved_thenAsksTheUserToSwitchAccounts() async {
        let stub = StubDocumentsService()
        await stub.enqueueInvite(success: DocumentsFixtures.invite(canClaim: false, wrongAccount: true))
        let viewModel = makeViewModel(stub)

        await viewModel.resolve()

        XCTAssertEqual(viewModel.nextStep, .wrongAccount)
    }

    func test_givenAlreadyClaimedInvite_whenResolved_thenAlreadyAcceptedWinsOverEveryOtherFlag() async {
        // Precedence check: a claimed invite still resolves, and the copy must
        // not tell someone to accept something they already have.
        let stub = StubDocumentsService()
        await stub.enqueueInvite(success: DocumentsFixtures.invite(
            needsAuth: true, canClaim: true, wrongAccount: true, accepted: true
        ))
        let viewModel = makeViewModel(stub)

        await viewModel.resolve()

        XCTAssertEqual(viewModel.nextStep, .alreadyAccepted)
    }

    // MARK: - Invalid input

    func test_givenBlankToken_whenResolving_thenRefusesBeforeTheService() async {
        let stub = StubDocumentsService()
        let viewModel = makeViewModel(stub, token: "   ")

        await viewModel.resolve()

        XCTAssertEqual(viewModel.error as? DocumentsUIError, .invalidInviteToken)
        XCTAssertNil(viewModel.invite)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - Upstream failure

    func test_givenUnknownOrExpiredToken_whenResolving_thenSurfacesTheErrorAndOffersNoHandOff() async {
        // With nothing resolved there is no invite to accept, so the footer
        // must not offer a link to a page that will 404 as well.
        let stub = StubDocumentsService()
        await stub.enqueueInvite(failure: DocumentsError.notFound)
        let viewModel = makeViewModel(stub)

        await viewModel.resolve()

        XCTAssertEqual(viewModel.error as? DocumentsError, .notFound)
        XCTAssertNil(viewModel.invite)
        XCTAssertNil(viewModel.nextStep)
        XCTAssertNil(viewModel.acceptURL)
    }

    // MARK: - Empty / boundary

    func test_givenInviteWithoutATitle_whenResolved_thenFallsBackToNeutralCopy() async {
        // The server may withhold the title; the landing still has to read.
        let stub = StubDocumentsService()
        await stub.enqueueInvite(success: DocumentsFixtures.invite(resourceTitle: nil))
        let viewModel = makeViewModel(stub)

        await viewModel.resolve()

        XCTAssertEqual(viewModel.displayTitle, "this document")
    }
}

// MARK: - URL parsing

final class DocumentInviteURLParserTests: XCTestCase {

    func test_givenWebInviteURL_whenParsed_thenExtractsTheToken() {
        // The address the invite email actually carries.
        let url = URL(string: "https://interlinedlist.com/documents/invite/xN3v9Qk")!
        XCTAssertEqual(DocumentInviteURLParser.parse(url)?.token, "xN3v9Qk")
    }

    func test_givenCustomSchemeInviteURL_whenParsed_thenExtractsTheTokenFromTheHostForm() {
        // `interlinedlist://documents/invite/tok` parses "documents" as the
        // *host*, not a path segment — the case a naive path-only parser drops.
        let url = URL(string: "interlinedlist://documents/invite/tok")!
        XCTAssertEqual(DocumentInviteURLParser.parse(url)?.token, "tok")
    }

    func test_givenShareLinkURL_whenParsed_thenIsNotTreatedAsAnInvite() {
        // A share link and an invite are different objects with different
        // routes; confusing them would resolve the wrong thing.
        let url = URL(string: "https://interlinedlist.com/documents/shared/tok")!
        XCTAssertNil(DocumentInviteURLParser.parse(url))
    }

    func test_givenListInviteURL_whenParsed_thenIsNotTreatedAsADocumentInvite() {
        // `/lists/invite/{token}` is the list equivalent with its own route.
        let url = URL(string: "https://interlinedlist.com/lists/invite/tok")!
        XCTAssertNil(DocumentInviteURLParser.parse(url))
    }

    func test_givenTokenlessInviteURL_whenParsed_thenReturnsNil() {
        // Boundary: a truncated paste.
        XCTAssertNil(DocumentInviteURLParser.parse(URL(string: "https://interlinedlist.com/documents/invite")!))
    }

    func test_givenPastedStringWithWhitespace_whenParsed_thenStillMatches() {
        XCTAssertEqual(
            DocumentInviteURLParser.parse(string: "  https://interlinedlist.com/documents/invite/tok\n")?.token,
            "tok"
        )
    }

    func test_givenEmptyString_whenParsed_thenReturnsNil() {
        XCTAssertNil(DocumentInviteURLParser.parse(string: "   "))
    }

    @MainActor
    func test_givenInviteURL_whenHandled_thenRoutesItAndReportsHandled() {
        var posted: ParsedDocumentInvite?
        let handled = DocumentInviteDeepLink.handle(
            URL(string: "https://interlinedlist.com/documents/invite/tok")!,
            post: { posted = $0 }
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(posted?.token, "tok")
    }

    @MainActor
    func test_givenOAuthCallbackURL_whenHandled_thenFallsThroughUntouched() {
        // The URL handler chains invite → share → OAuth; a non-invite URL must
        // report `false` so the next handler still sees it.
        var posted: ParsedDocumentInvite?
        let handled = DocumentInviteDeepLink.handle(
            URL(string: "interlinedlist://oauth/callback?code=abc")!,
            post: { posted = $0 }
        )

        XCTAssertFalse(handled)
        XCTAssertNil(posted)
    }
}
