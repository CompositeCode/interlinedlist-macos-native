import Foundation

/// Request builders for the **LinkedIn posting targets** API group (the-gaps.md
/// G11a) — the destinations the user can cross-post to on LinkedIn (their
/// personal profile and, when the org scope is granted, org pages).
///
/// Paths + shapes verified live 2026-07-31 (read-only). The org-page half
/// (`/api/orgs/{id}/linkedin-page`) is **not deployed** live (G11b, deferred).
public enum LinkedIn {

    /// `GET /api/linkedin/posting-targets` — targets with their enabled state,
    /// plus `orgScopeMissing` when org pages are unavailable.
    public static func postingTargets() -> Request<LinkedInPostingTargetsResponse> {
        Request(method: .get, path: "/api/linkedin/posting-targets", auth: .bearer)
    }

    /// `GET /api/linkedin/targets` — the available targets (no enabled state).
    public static func targets() -> Request<LinkedInPostingTargetsResponse> {
        Request(method: .get, path: "/api/linkedin/targets", auth: .bearer)
    }
}
