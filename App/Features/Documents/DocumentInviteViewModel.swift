// DocumentInviteViewModel
//
// Drives `DocumentInviteView` — the landing shown when a document email
// invite is opened, whether pasted or delivered via the `interlinedlist://`
// deep-link scheme (work-consolidation.md G24).
//
// It resolves the token through `GET /api/documents/invite/{token}` and
// surfaces the document title, the granted role, and which branch of the
// landing applies (sign in / wrong account / ready to accept / already
// accepted).
//
// **There is no accept intent, and there will not be one until the backend
// changes.** `POST /api/documents/invite/{token}` is `x-auth-type: session`
// in the live spec — authenticated by the browser session cookie only — so a
// Bearer sync-token client cannot claim an invite however the request is
// shaped. The view model's job ends at "here is what this invite is"; the
// accept step is handed to the browser via `acceptURL`. That is a backend
// constraint filed separately, not a gap in this layer, so this deliberately
// does *not* mirror `ResolveShareViewModel.claimAccess()`.
//
// Reads through `DocumentsServicing` only. Per decision 0003, this view model
// consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class DocumentInviteViewModel {

    // MARK: - Dependencies

    private let documents: DocumentsServicing

    /// The opaque token this landing resolves.
    let token: String

    /// Base web address used to build the browser hand-off. Injected so tests
    /// don't need the environment.
    private let webBaseURL: URL

    // MARK: - Observable state

    /// The resolved invite once `resolve()` succeeds. `nil` before the first
    /// resolve or after a failure.
    private(set) var invite: DocumentInvite?

    /// True while the resolve round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed resolve.
    private(set) var error: Error?

    // MARK: - Init

    init(documents: DocumentsServicing, token: String, webBaseURL: URL) {
        self.documents = documents
        self.token = token
        self.webBaseURL = webBaseURL
    }

    // MARK: - Derived UI state

    /// The document title to show, falling back to a neutral phrase when the
    /// server withheld it.
    var displayTitle: String {
        invite?.resourceTitle ?? "this document"
    }

    /// The address that completes the invite in a browser. Always available
    /// once resolved — accepting is browser-only, so this is the primary
    /// action rather than a fallback.
    var acceptURL: URL? {
        invite?.acceptURL(base: webBaseURL)
    }

    /// What the landing should tell the person to do next. Ordered by
    /// precedence: an already-claimed invite is terminal, then the two
    /// account problems, then the ready case.
    enum NextStep: Equatable {
        /// Already claimed — nothing to do but open the document.
        case alreadyAccepted
        /// Nobody is signed in on the web; they must sign in there first.
        case signInInBrowser
        /// Signed in on the web under a different address than the invite.
        case wrongAccount
        /// Everything lines up — finish in the browser.
        case acceptInBrowser
    }

    /// The branch to render, or `nil` before the invite resolves.
    var nextStep: NextStep? {
        guard let invite else { return nil }
        if invite.accepted { return .alreadyAccepted }
        if invite.needsAuth { return .signInInBrowser }
        if invite.wrongAccount { return .wrongAccount }
        return .acceptInBrowser
    }

    // MARK: - Intents

    /// Resolves the token, populating `invite`. Refuses a blank token before
    /// the service call. Re-entrant-safe: a second call while one is in flight
    /// is dropped.
    func resolve() async {
        guard !isLoading else { return }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            invite = nil
            error = DocumentsUIError.invalidInviteToken
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            invite = try await documents.invite(token: trimmed)
            error = nil
        } catch {
            // The server collapses unknown / expired / revoked / deleted into
            // one 404 so tokens can't be probed. Keep that collapse — do not
            // guess which of the four it was.
            invite = nil
            self.error = error
        }
    }
}
