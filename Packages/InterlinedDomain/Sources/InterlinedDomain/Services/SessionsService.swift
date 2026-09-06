import Foundation
import InterlinedKit

/// The active-sessions surface the App layer codes against
/// (work-consolidation.md G19).
public protocol SessionsServicing: Sendable {
    /// Every active session, current one included.
    func sessions() async throws -> [ActiveSession]
    /// Revokes one session by id.
    func revoke(sessionID: String) async throws
}

/// Reads `GET /api/user/sessions` and revokes via
/// `DELETE /api/user/sessions/{id}`.
///
/// Unlike `ContentLimitsService` these calls **throw** rather than falling back:
/// a security pane that silently showed a stale or empty session list would be
/// actively misleading, so the caller must surface the failure.
public final class SessionsService: SessionsServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func sessions() async throws -> [ActiveSession] {
        let response = try await api.send(Sessions.list())
        return response.sessions.map(ActiveSession.init(from:))
    }

    public func revoke(sessionID: String) async throws {
        // `sendVoid` — the revoke response body carries nothing the client needs.
        try await api.sendVoid(Sessions.revoke(id: sessionID))
    }
}
