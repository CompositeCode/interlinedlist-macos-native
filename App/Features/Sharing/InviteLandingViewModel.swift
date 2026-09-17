// InviteLandingViewModel
//
// Drives `InviteLandingView` — the landing shown when the user opens a
// `…/lists/invite/{token}` link, pasted or delivered via the
// `interlinedlist://` deep-link scheme (work-consolidation.md G23 / issue #48).
//
// **There is no native Accept.** `POST /api/lists/invite/{token}` is declared
// `x-auth-type: session` in the live OpenAPI spec, so a Bearer-only macOS
// client cannot claim an invite at all. Shipping an Accept button here would
// ship a guaranteed 401, so the landing shows what the invite grants and hands
// the accept step to the browser. When the backend exposes a Bearer-reachable
// claim route, `acceptInBrowserURL` is the seam that gets replaced with a real
// `claim()` intent — nothing else here changes.
//
// Accepting an invite is documented as always free, so no entitlement gate
// belongs anywhere in this flow.
//
// Reads through `SharingServicing` only. Per decision 0003 it consumes only
// `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class InviteLandingViewModel {

    // MARK: - Dependencies

    private let service: SharingServicing
    let parsed: ParsedShare
    /// Where the browser hand-off points. Injected so the view model stays
    /// free of any environment lookup and is trivially unit-testable.
    private let webBaseURL: URL

    // MARK: - Observable state

    /// The resolved invite once `resolve()` succeeds.
    private(set) var invite: ResolvedListInvite?

    /// True while the resolve round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed resolve. An unknown,
    /// expired, or revoked token arrives here as an `APIError.notFound` — the
    /// server makes those three cases deliberately indistinguishable.
    private(set) var error: Error?

    /// True when the link is an invite for a resource this client cannot
    /// resolve. Only list invites have a domain path today (issue #48 scopes
    /// the work to Lists); a document invite still gets a usable landing that
    /// sends the user to the browser rather than silently doing nothing.
    private(set) var isUnsupportedResource: Bool = false

    // MARK: - Init

    init(service: SharingServicing, parsed: ParsedShare, webBaseURL: URL) {
        self.service = service
        self.parsed = parsed
        self.webBaseURL = webBaseURL
    }

    // MARK: - Derived UI state

    /// The web address that completes the invite. Always offered — it is the
    /// only route to acceptance from this client.
    var acceptInBrowserURL: URL? {
        ShareURLParser.webURL(
            base: webBaseURL,
            kind: parsed.kind,
            token: parsed.token,
            mode: .invite
        )
    }

    /// One line explaining what the user should do next, chosen from the flags
    /// the landing payload returns. Ordered most-specific first: an already
    /// accepted invite is a dead end regardless of who is signed in, and a
    /// wrong-account signal outranks a plain "sign in".
    var guidance: String {
        guard let invite else { return "" }
        if invite.accepted {
            return "This invite has already been accepted."
        }
        if invite.wrongAccount {
            return "You're signed in with a different email than the one invited. Switch accounts in your browser to accept."
        }
        if invite.needsAuth {
            return "Sign in on the web to accept this invite."
        }
        if invite.canClaim {
            return "This invite is ready to accept. Accepting happens in your browser — the app can't complete it yet."
        }
        return "Open this invite in your browser to accept it."
    }

    // MARK: - Intents

    /// Resolves the token, populating `invite` (role / title / flags).
    func resolve() async {
        guard !isLoading else { return }
        guard parsed.kind == .list else {
            // Not an error — just outside what this client can read today.
            isUnsupportedResource = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            invite = try await service.resolveListInvite(token: parsed.token)
            error = nil
        } catch {
            invite = nil
            self.error = error
        }
    }
}
