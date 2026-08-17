// ShareLinksViewModel
//
// Drives `ShareLinksView` — the "Links" tab of the share panel for a list
// or a document (work-consolidation.md G3). Owns the loaded active links, the create
// form state (role + optional expiry), the loading / error state, and the
// create / copy / revoke intents. Reads through `SharingServicing` only —
// no direct API or entitlements access — so unit tests substitute a stub
// service.
//
// Target dispatch: a `ShareTarget` selects the list vs. document half of
// the service. Every intent forks on `target` once and calls the matching
// pair, so the view layer stays target-agnostic.
//
// Subscriber gate: link *creation* is subscriber-only. The domain service
// throws `SharingError.subscriberRequired` before any HTTP when the account
// is not a subscriber. This view model catches that specific case and
// raises `showSubscriberUpsell` instead of surfacing a raw error, so the
// view can present an upsell rather than an error banner (mirrors
// `ListFoldersViewModel`). Every other failure flows into `error`.
//
// Optimistic revoke: revoking prunes the link from the rendered list
// immediately, calls the service, and restores the snapshot on failure
// (the proven M2 optimistic pattern). A per-token debounce set guards
// against a rapid double-tap double-firing the revoke.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ShareLinksViewModel {

    // MARK: - Dependencies

    private let service: SharingServicing
    let target: ShareTarget

    // MARK: - Observable state

    /// The active (non-revoked) links returned by the most recent load or
    /// create. Roots the "Active links" list in the panel.
    private(set) var links: [ShareLink] = []

    /// True while the initial load / a refresh round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// True while a create round-trip is in flight (drives the form's
    /// spinner / disabled state independently of a background refresh).
    private(set) var isCreating: Bool = false

    /// Surfaced error from the most recent failed load / create / revoke.
    /// The subscriber-gate case is routed to `showSubscriberUpsell`
    /// instead, so this never carries a `subscriberRequired`.
    private(set) var error: Error?

    /// Raised when a create was blocked because the account is not a
    /// subscriber. The view presents an upsell instead of an error banner.
    /// Reset by `dismissUpsell()` or the next successful create.
    private(set) var showSubscriberUpsell: Bool = false

    /// True once the first load has resolved (success or failure). Lets the
    /// view distinguish "loading" from "no links yet".
    private(set) var hasLoadedOnce: Bool = false

    // MARK: - Create-form state (bound by the view)

    /// The role the next created link will grant. Bound to the role picker.
    var newRole: ShareRole = .watcher

    /// The optional expiry for the next created link. `nil` == never
    /// expires. Bound to the expiry controls (a toggle + date picker in the
    /// view).
    var newExpiresAt: Date?

    // MARK: - Internals

    /// Per-token debounce set so a rapid double-tap on revoke doesn't
    /// double-fire the service call (proven M2 pattern).
    private var pendingRevocations: Set<String> = []

    // MARK: - Init

    init(service: SharingServicing, target: ShareTarget) {
        self.service = service
        self.target = target
    }

    // MARK: - Intents

    /// First-time + refresh load. Replaces the rendered active-links list
    /// with the server's authoritative set.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await fetchLinks()
            links = Self.activeOnly(all)
            error = nil
            hasLoadedOnce = true
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
    }

    /// Creates a link with the current form's role + expiry, then prepends
    /// the server's authoritative link to the rendered list. A
    /// `subscriberRequired` failure raises the upsell instead of an error;
    /// any other failure flows into `error`. Returns the created link on
    /// success so the caller can, e.g., immediately offer it for sharing.
    @discardableResult
    func create() async -> ShareLink? {
        guard !isCreating else { return nil }
        showSubscriberUpsell = false
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await createLink(role: newRole, expiresAt: newExpiresAt)
            // Trust the server's return, not a locally-synthesized link
            // (proven optimistic-return pattern). Prepend so the newest
            // link is first.
            links.insert(created, at: 0)
            error = nil
            return created
        } catch SharingError.subscriberRequired {
            showSubscriberUpsell = true
            return nil
        } catch {
            self.error = error
            return nil
        }
    }

    /// Revokes a link. Optimistic: prune it from the rendered list, call
    /// the service, restore the snapshot on failure (proven M2 pattern).
    /// The per-token debounce set guards a rapid double-tap.
    func revoke(token: String) async {
        guard !pendingRevocations.contains(token) else { return }
        pendingRevocations.insert(token)
        defer { pendingRevocations.remove(token) }
        let snapshot = links
        links.removeAll { $0.token == token }
        do {
            let revoked = try await revokeLink(token: token)
            if revoked {
                error = nil
            } else {
                // Server reported the token was not revoked — restore so
                // the UI reflects the true state.
                links = snapshot
            }
        } catch {
            links = snapshot
            self.error = error
        }
    }

    /// Dismisses the subscriber upsell (the "Upgrade" affordance was shown /
    /// cancelled).
    func dismissUpsell() {
        showSubscriberUpsell = false
    }

    /// Convenience for tests + previews — seed the rendered list without a
    /// service round-trip.
    func seedForTest(links: [ShareLink]) {
        self.links = links
        self.hasLoadedOnce = true
    }

    // MARK: - Target dispatch

    private func fetchLinks() async throws -> [ShareLink] {
        switch target {
        case .list(let id): return try await service.listShareLinks(listId: id)
        case .document(let id): return try await service.documentShareLinks(documentId: id)
        }
    }

    private func createLink(role: ShareRole, expiresAt: Date?) async throws -> ShareLink {
        switch target {
        case .list(let id):
            return try await service.createListShareLink(listId: id, role: role, expiresAt: expiresAt)
        case .document(let id):
            return try await service.createDocumentShareLink(documentId: id, role: role, expiresAt: expiresAt)
        }
    }

    private func revokeLink(token: String) async throws -> Bool {
        switch target {
        case .list(let id): return try await service.revokeListShareLink(listId: id, token: token)
        case .document(let id): return try await service.revokeDocumentShareLink(documentId: id, token: token)
        }
    }

    // MARK: - Pure helpers

    /// Keeps only links the server still resolves (not revoked). Pure.
    private static func activeOnly(_ links: [ShareLink]) -> [ShareLink] {
        links.filter { !$0.isRevoked }
    }
}
