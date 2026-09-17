// IntegrationsViewModel
//
// Drives Settings ▸ Integrations (GitHub #47 / G33) — the pane that manages
// every connected provider in one place.
//
// `LinkedAccountsView` could only **link**. Once an account was connected there
// was no way to check it, reconfigure it, or remove it from the Mac; the web's
// `/integrations` page does all four.
//
// Three things here come from the 2026-09-15 probe rather than from the docs:
//
//  - **Mastodon arrives instance-qualified** (`"mastodon:techhub.social"`), so
//    every Mastodon identity used to decode as an unknown provider. Fixed in
//    `IdentityProvider`; this pane is where it becomes visible, as one row per
//    instance.
//  - **X was missing from the client's provider list**, despite the account
//    having a linked X identity and cross-posting to X being shipped.
//  - **`GET /api/user/identities` accepts Bearer**, contrary to its `.session`
//    annotation — a redundant cookie login on every load.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class IntegrationsViewModel {

    private let user: UserServicing

    // MARK: - Observable state

    private(set) var identities: [LinkedIdentity] = []

    /// The app's GitHub configuration, when the status read succeeded.
    private(set) var github: GitHubConnection?

    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// Identities with a verify in flight, keyed by identity id.
    private(set) var verifyingIDs: Set<String> = []

    /// Identities with a disconnect in flight.
    private(set) var disconnectingIDs: Set<String> = []

    /// The outcome of the most recent verify per identity. `true` means the
    /// connection answered; `false` means it did not.
    ///
    /// Per-row on purpose: a pane with five providers and one shared status
    /// line cannot say *which* connection is broken, which is the only thing
    /// the user needs to know.
    private(set) var verifyResults: [String: Bool] = [:]

    /// The error from the most recent failed action on a row, keyed by identity
    /// id, so a failure reports where it happened.
    private(set) var rowErrors: [String: String] = [:]

    // MARK: - Projections

    /// Every provider the pane shows a row for, in a stable order: the
    /// connected ones first, then the ones that could be connected.
    var connectedIdentities: [LinkedIdentity] {
        identities.sorted { lhs, rhs in
            if lhs.provider.displayName != rhs.provider.displayName {
                return lhs.provider.displayName < rhs.provider.displayName
            }
            // Several Mastodon instances sort by host, so the list is stable
            // across loads rather than following server order.
            return (lhs.instance ?? "") < (rhs.instance ?? "")
        }
    }

    /// Providers with no connection yet.
    ///
    /// Mastodon is **never** listed here even when instances are already
    /// connected: it supports several, so "connect another instance" stays
    /// available. Every other provider disappears from this list once linked.
    var connectableProviders: [IdentityProvider] {
        let connected = Set(identities.map(\.provider))
        return [.github, .mastodon, .bluesky, .linkedin, .twitter].filter { provider in
            provider.supportsMultipleInstances || !connected.contains(provider)
        }
    }

    // MARK: - Init

    init(user: UserServicing) {
        self.user = user
    }

    // MARK: - Intents

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            identities = try await user.identities()
        } catch {
            loadError = error
            return
        }
        // The GitHub status is a soft follow-up: the pane is fully usable
        // without it, and only the GitHub row loses an affordance.
        github = try? await user.githubConnectionStatus()
    }

    func verify(_ identity: LinkedIdentity) async {
        guard !verifyingIDs.contains(identity.id) else { return }
        verifyingIDs.insert(identity.id)
        rowErrors[identity.id] = nil
        defer { verifyingIDs.remove(identity.id) }
        do {
            verifyResults[identity.id] = try await user.verifyIdentity(identity)
        } catch {
            // A failed verify is not a failed connection — the request itself
            // did not complete — so the row reports the error rather than
            // claiming the provider is broken.
            rowErrors[identity.id] = error.localizedDescription
        }
    }

    /// Disconnects a provider.
    ///
    /// Not optimistic. Disconnecting stops cross-posting, and a row that
    /// disappears and then comes back because the write failed is worse than a
    /// row that waits — the user needs to know whether it actually happened.
    func disconnect(_ identity: LinkedIdentity) async {
        guard !disconnectingIDs.contains(identity.id) else { return }
        disconnectingIDs.insert(identity.id)
        rowErrors[identity.id] = nil
        defer { disconnectingIDs.remove(identity.id) }
        do {
            try await user.unlinkIdentity(identity)
            identities.removeAll { $0.id == identity.id }
            verifyResults[identity.id] = nil
        } catch {
            rowErrors[identity.id] = error.localizedDescription
        }
    }

    /// What a disconnect confirmation should say stops working.
    ///
    /// Named per provider rather than a generic "are you sure": the consequence
    /// is the question, and it differs — losing GitHub takes GitHub-backed lists
    /// with it, losing a cross-post provider silently stops those posts.
    func disconnectConsequence(for identity: LinkedIdentity) -> String {
        switch identity.provider {
        case .github:
            return "Disconnecting GitHub stops GitHub-backed lists from syncing and signs this app out of GitHub Issues."
        case .mastodon:
            let host = identity.instance.map { " on \($0)" } ?? ""
            return "Disconnecting Mastodon\(host) stops cross-posting to that instance."
        case .bluesky, .linkedin, .twitter:
            return "Disconnecting \(identity.provider.displayName) stops cross-posting to it."
        case .other(let raw):
            return "Disconnecting \(raw) may stop features that depend on it."
        }
    }

    func isVerifying(_ identity: LinkedIdentity) -> Bool { verifyingIDs.contains(identity.id) }
    func isDisconnecting(_ identity: LinkedIdentity) -> Bool { disconnectingIDs.contains(identity.id) }
}
