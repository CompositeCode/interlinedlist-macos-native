// LinkedAccountsViewModel
//
// Drives the Settings > "Linked accounts" pane (PLAN.md §1 "Profile &
// account / linked identities", §6 M6 — "OAuth identity linking").
//
// Native OAuth completion is blocked upstream (the registered callback is
// a web URL, not a custom scheme — see `docs/spikes/0002-oauth-identity-
// linking.md`), so the approved v1 is a browser handoff: the view model
// resolves the authorize URL via `UserServicing.identityLinkURL(...)` and
// the view opens it with SwiftUI's `openURL` in the default browser. New
// identities appear after the user returns and taps Refresh.
//
// Reads through `UserServicing` only — no direct API access, no AppKit —
// so unit tests substitute a stub. `@Observable` so SwiftUI re-renders on
// every state change.
//
// Per decision 0003, the view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class LinkedAccountsViewModel {

    // MARK: - Dependencies

    private let user: UserServicing

    // MARK: - Observable state

    private(set) var identities: [LinkedIdentity] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// The most recent error from resolving a link URL (e.g. an unsupported
    /// provider or a missing Mastodon instance). Surfaced inline so the user
    /// learns why a "Link account" button did nothing.
    private(set) var linkError: Error?

    // MARK: - Init

    init(userService: UserServicing) {
        self.user = userService
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

    /// Resolves the browser-handoff authorize URL for linking a provider.
    /// Returns `nil` (and records `linkError`) when the URL cannot be built —
    /// an unsupported provider or a Mastodon link with no instance host.
    ///
    /// The view opens the returned URL with `openURL`; this view model never
    /// touches AppKit or `NSWorkspace` (SwiftUI-only rule).
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
}
