// LinkedAccountsViewModel
//
// Drives the Settings > "Linked accounts" pane (PLAN.md §1 "Profile &
// account / linked identities", §6 M6 — "OAuth identity linking").
//
// NW-5: native in-app OAuth via `ASWebAuthenticationSession`. The view
// model resolves the authorize URL with `redirect_uri=interlinedlist://oauth/callback`
// via `UserServicing.identityLinkURLNative(...)`, runs an in-app session,
// then calls `UserServicing.linkIdentityNative(...)` with the returned
// code + state. The seam is `OAuthSessionAuthenticating` (a protocol in
// this file) so the flow is unit-testable without a real browser.
//
// Reads through `UserServicing` only — no direct API access, no AppKit —
// so unit tests substitute stubs. `@Observable` so SwiftUI re-renders on
// every state change.
//
// Per decision 0003, the view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import AuthenticationServices
import InterlinedDomain

// MARK: - OAuthSessionAuthenticating

/// Protocol seam for the native OAuth browser session so `LinkedAccountsViewModel`
/// is testable without launching a real `ASWebAuthenticationSession`.
protocol OAuthSessionAuthenticating: Sendable {
    /// Presents the OAuth authorize URL to the user and returns the callback URL
    /// (with `code` and `state` query parameters) once the user completes auth.
    /// Throws when the session is cancelled or encounters an error.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

// MARK: - ASWebAuthenticationSessionAuthenticator

/// Production implementation that wraps `ASWebAuthenticationSession`.
/// Uses the macOS 14.4+ `callback: .customScheme(_)` API which does not
/// require a `presentationContextProvider`.
struct ASWebAuthenticationSessionAuthenticator: OAuthSessionAuthenticating, Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackScheme)
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: LinkedAccountsError.noCallback)
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

// MARK: - LinkedAccountsError

enum LinkedAccountsError: Error, LocalizedError, Equatable {
    case noCallback
    case missingCallbackParams

    var errorDescription: String? {
        switch self {
        case .noCallback:
            return "The authentication session ended without a callback URL."
        case .missingCallbackParams:
            return "The OAuth callback was missing the required code or state."
        }
    }
}

// MARK: - LinkedAccountsViewModel

@MainActor
@Observable
final class LinkedAccountsViewModel {

    // MARK: - Dependencies

    private let user: UserServicing
    private let oauthSession: OAuthSessionAuthenticating

    // MARK: - Observable state

    private(set) var identities: [LinkedIdentity] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// The most recent error from a link attempt (URL resolution or session).
    private(set) var linkError: Error?

    /// True while a native OAuth session is in flight.
    private(set) var isLinking: Bool = false

    /// True after a successful native link — the view shows a brief success banner.
    private(set) var nativeLinkSuccess: Bool = false

    // MARK: - Init

    init(
        userService: UserServicing,
        oauthSession: OAuthSessionAuthenticating = ASWebAuthenticationSessionAuthenticator()
    ) {
        self.user = userService
        self.oauthSession = oauthSession
    }

    // MARK: - Loading

    /// Loads (or refreshes) the signed-in account's linked identities.
    /// Bound to the view's `.task` and the Refresh button.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            identities = try await user.identities()
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// The providers offered as "Link account" buttons. Mastodon is included
    /// but requires the instance prompt before a URL can be resolved (the
    /// view collects the instance host). `.other` is never offered — there is
    /// no authorize route the client can build for an unknown provider.
    var linkableProviders: [IdentityProvider] {
        [.github, .mastodon, .bluesky, .linkedin]
    }

    // MARK: - Legacy browser-handoff (kept for tests that rely on it)

    /// Resolves the browser-handoff authorize URL for linking a provider.
    /// Returns `nil` (and records `linkError`) when the URL cannot be built.
    func linkURL(for provider: IdentityProvider, instance: String? = nil) -> URL? {
        do {
            let url = try user.identityLinkURL(provider: provider, instance: instance)
            linkError = nil
            return url
        } catch {
            linkError = error
            return nil
        }
    }

    // MARK: - NW-5 Native OAuth

    /// Runs a native in-app OAuth linking session for the given provider.
    ///
    /// Flow:
    /// 1. Resolve the native authorize URL (with `redirect_uri=interlinedlist://oauth/callback`).
    /// 2. Present the URL via `OAuthSessionAuthenticating.authenticate(url:callbackScheme:)`.
    /// 3. Parse `code` + `state` from the callback URL.
    /// 4. Exchange via `UserServicing.linkIdentityNative(provider:code:state:)`.
    /// 5. Append the returned identity and set `nativeLinkSuccess = true`.
    ///
    /// On any failure, sets `linkError` and leaves state unchanged.
    func linkNatively(provider: IdentityProvider, instance: String? = nil) async {
        guard !isLinking else { return }
        isLinking = true
        linkError = nil
        nativeLinkSuccess = false
        defer { isLinking = false }

        do {
            let authURL = try user.identityLinkURLNative(provider: provider, instance: instance)
            let callbackURL = try await oauthSession.authenticate(url: authURL, callbackScheme: "interlinedlist")

            guard
                let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                let state = components.queryItems?.first(where: { $0.name == "state" })?.value
            else {
                throw LinkedAccountsError.missingCallbackParams
            }

            let newIdentity = try await user.linkIdentityNative(provider: provider, code: code, state: state)
            identities.append(newIdentity)
            nativeLinkSuccess = true
        } catch {
            linkError = error
        }
    }
}
