import Foundation

/// Request builders for **active sessions & token revocation**
/// (work-consolidation.md G19) — the Settings ▸ Security pane.
///
/// `GET /api/user/sessions` is recorded in the gap definition as
/// **Bearer-reachable** (unlike the session-cookie-only `/api/auth/accounts`
/// that blocks G10 multi-account), so both builders use `.bearer`.
public enum Sessions {

    /// `GET /api/user/sessions` — the account's active sessions.
    public static func list() -> Request<SessionsResponse> {
        Request(method: .get, path: "/api/user/sessions", auth: .bearer)
    }

    /// `DELETE /api/user/sessions/{id}` — revoke one session.
    ///
    /// Returns `EmptyResponse` because the revoke body carries nothing the
    /// client needs; callers use `sendVoid` and re-read the list.
    public static func revoke(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/user/sessions/\(id)", auth: .bearer)
    }
}
