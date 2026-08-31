// InvitesViewModel
//
// Drives `InvitesView` — the "Invite by email" section of the web sharing
// dialog (work-consolidation.md G3) for a list or a document. Owns the loaded
// invites ("Pending invites"), the compose form (email + role + optional
// expiry), the send / revoke intents, and the loading / error state. Reads
// through `SharingServicing` only — no direct API or entitlements access — so
// unit tests substitute a stub service.
//
// Target dispatch: a `ShareTarget` selects the list vs. document half of the
// service, so the view layer builds one panel regardless of resource.
//
// Send-then-refresh: the create endpoint returns a lightweight `SentInvite`
// (email/role/expiry + a claim url) but not a revocable row, so a successful
// send re-fetches the authoritative invite list to surface the new "Pending"
// row with its revoke token. The returned claim url is retained as
// `lastSentURL` so the view can offer to share it.
//
// Subscriber gate: sending an invite is subscriber-only — the domain service
// throws `SharingError.subscriberRequired` before any HTTP; this view model
// catches that specific case and raises `showSubscriberUpsell` instead of a
// raw error (mirrors `ShareLinksViewModel`). Listing and revoking are not
// gated.
//
// Optimistic revoke: revoking prunes the row immediately, calls the service,
// and restores the snapshot on failure. A per-token debounce guards a
// double-tap.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

/// Client-side validation failures raised before any service call.
enum InvitesError: LocalizedError, Equatable {
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Enter a valid email address."
        }
    }
}

@MainActor
@Observable
final class InvitesViewModel {

    // MARK: - Dependencies

    private let service: SharingServicing
    let target: ShareTarget

    // MARK: - Observable state

    /// The invites returned by the most recent load / send-refresh — roots the
    /// "Pending invites" table (which also renders accepted rows).
    private(set) var invites: [ShareInvite] = []

    /// True while the initial load / a refresh round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// True while a send round-trip (create + refresh) is in flight.
    private(set) var isSending: Bool = false

    /// Surfaced error from the most recent failed load / send / revoke, or a
    /// client-side `InvitesError`. The subscriber-gate case is routed to
    /// `showSubscriberUpsell` instead.
    private(set) var error: Error?

    /// Raised when a send was blocked because the account is not a subscriber.
    private(set) var showSubscriberUpsell: Bool = false

    /// True once the first load has resolved. Distinguishes "loading" from
    /// "no invites yet".
    private(set) var hasLoadedOnce: Bool = false

    /// The claim url from the most recent successful send, so the view can
    /// offer to share it. Cleared on the next send or by `clearSentURL()`.
    private(set) var lastSentURL: URL?

    // MARK: - Compose-form state (bound by the view)

    /// The invitee email. Bound to the email field.
    var newEmail: String = ""

    /// The role the invite grants. Bound to the role picker.
    var newRole: ShareRole = .watcher

    /// Optional expiry for the invite. `nil` == never expires.
    var newExpiresAt: Date?

    // MARK: - Internals

    private var pendingRevocations: Set<String> = []

    // MARK: - Init

    init(service: SharingServicing, target: ShareTarget) {
        self.service = service
        self.target = target
    }

    // MARK: - Intents

    /// First-time + refresh load. Replaces the rendered invite list with the
    /// server's authoritative set.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            invites = try await fetchInvites()
            error = nil
            hasLoadedOnce = true
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
    }

    /// Validates + sends an email invite with the current form's email / role /
    /// expiry, then re-fetches the invite list so the new row (with its revoke
    /// token) appears. A blank / malformed email is rejected before any HTTP —
    /// no service call is made. A `subscriberRequired` failure raises the
    /// upsell; any other failure surfaces the error.
    func send() async {
        guard !isSending else { return }
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(trimmed) else {
            error = InvitesError.invalidEmail
            return
        }
        showSubscriberUpsell = false
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await createInvite(email: trimmed, role: newRole, expiresAt: newExpiresAt)
            lastSentURL = sent.url
            newEmail = ""
            error = nil
            // The create response is not a revocable row — refresh to surface
            // the authoritative "Pending" entry with its token.
            invites = (try? await fetchInvites()) ?? invites
        } catch SharingError.subscriberRequired {
            showSubscriberUpsell = true
        } catch {
            self.error = error
        }
    }

    /// Revokes an invite. Optimistic: prune it, call the service, restore the
    /// snapshot when the server reports it was not revoked or the call fails.
    func revoke(token: String) async {
        guard !pendingRevocations.contains(token) else { return }
        pendingRevocations.insert(token)
        defer { pendingRevocations.remove(token) }

        let snapshot = invites
        invites.removeAll { $0.token == token }
        do {
            let revoked = try await revokeInvite(token: token)
            if revoked {
                error = nil
            } else {
                invites = snapshot
            }
        } catch {
            invites = snapshot
            self.error = error
        }
    }

    /// Dismisses the subscriber upsell.
    func dismissUpsell() {
        showSubscriberUpsell = false
    }

    /// Clears the retained claim url once the view has offered / dismissed it.
    func clearSentURL() {
        lastSentURL = nil
    }

    // MARK: - Test seams

    func seedForTest(invites: [ShareInvite]) {
        self.invites = invites
        self.hasLoadedOnce = true
    }

    // MARK: - Target dispatch

    private func fetchInvites() async throws -> [ShareInvite] {
        switch target {
        case .list(let id): return try await service.listInvites(listId: id)
        case .document(let id): return try await service.documentInvites(documentId: id)
        }
    }

    private func createInvite(email: String, role: ShareRole, expiresAt: Date?) async throws -> SentInvite {
        switch target {
        case .list(let id):
            return try await service.createListInvite(listId: id, email: email, role: role, expiresAt: expiresAt)
        case .document(let id):
            return try await service.createDocumentInvite(documentId: id, email: email, role: role, expiresAt: expiresAt)
        }
    }

    private func revokeInvite(token: String) async throws -> Bool {
        switch target {
        case .list(let id): return try await service.revokeListInvite(listId: id, token: token)
        case .document(let id): return try await service.revokeDocumentInvite(documentId: id, token: token)
        }
    }

    // MARK: - Pure helpers

    /// Minimal email sanity check — a non-empty local part, an `@`, and a dot
    /// in the domain. Pure; keeps a malformed address from reaching the API.
    static func isValidEmail(_ email: String) -> Bool {
        guard let at = email.firstIndex(of: "@") else { return false }
        let local = email[email.startIndex..<at]
        let domain = email[email.index(after: at)...]
        return !local.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}
