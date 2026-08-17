import Foundation

/// Request builder for the **Limits** endpoint (work-consolidation.md G14) —
/// machine-readable upload + message limits so the composer can validate
/// message length (and, for display, media size) against server-authoritative
/// values instead of hard-coded constants.
///
/// Path + shape verified live 2026-07-31: `GET /api/limits` returns the media
/// image/video ceilings and `message.maxContentLength`. The route does not
/// require auth, but the builder sends `.bearer` for consistency with the rest
/// of the API surface (the route accepts it).
///
/// Follows the `Request.swift` conventions: a factory returning `Request<DTO>`,
/// explicit auth, a path-only URL, and no throwing.
public enum Limits {

    /// `GET /api/limits` — the current media + message limits.
    public static func get() -> Request<LimitsDTO> {
        Request(method: .get, path: "/api/limits", auth: .bearer)
    }
}
