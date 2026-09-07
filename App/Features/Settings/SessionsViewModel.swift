// SessionsViewModel
//
// Drives Settings ▸ Security — the account's active sessions with a per-row
// Revoke action (work-consolidation.md G19).
//
// Reads through `SessionsServicing` only, so a stub drives the tests without
// networking. Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class SessionsViewModel {

    private let service: SessionsServicing?

    private(set) var sessions: [ActiveSession] = []
    private(set) var isLoading = false
    /// The session id currently being revoked, so only that row shows a spinner.
    private(set) var revokingID: String?
    private(set) var error: Error?

    /// True when the feature has no service wired (see `AppEnvironment.sessions`).
    var isUnavailable: Bool { service == nil }

    init(service: SessionsServicing?) {
        self.service = service
    }

    func load() async {
        guard let service else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // Current session first, then most-recently-used — the row a user
            // looks for is either "this Mac" or the one that just appeared.
            sessions = try await service.sessions().sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
                return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
            }
        } catch {
            self.error = error
        }
    }

    /// Revokes one session and drops it from the list on success.
    ///
    /// Revoking the *current* session signs this app out, so the view guards
    /// that behind a confirmation; this method does not re-check, it just
    /// performs what it was asked.
    func revoke(_ session: ActiveSession) async {
        guard let service, revokingID == nil else { return }
        revokingID = session.id
        error = nil
        defer { revokingID = nil }
        do {
            try await service.revoke(sessionID: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            self.error = error
        }
    }
}
