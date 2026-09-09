import Foundation

// MARK: - LinkedIn posting-target DTOs (work-consolidation.md G11a)
//
// Shapes verified live 2026-07-31 (read-only):
//   GET /api/linkedin/posting-targets
//       -> { targets: [{ kind, label, avatarUrl, enabled }], orgScopeMissing }
//   GET /api/linkedin/targets
//       -> { targets: [{ kind, label, avatarUrl }] }
//
// CORRECTED 2026-09-09 (work-consolidation.md G25) from the published
// reference at /help/api/linkedin-integration. `kind` is one of THREE tokens,
// not two:
//
//   { "kind": "personal",     "label": "Alice Example", "avatarUrl": "…" }
//   { "kind": "orgPage",      "pageId": "<uuid>",         "linkedInPageId": "12345678",
//     "label": "Acme Corp",   "logoUrl": "…" }
//   { "kind": "personalPage", "personalPageId": "<uuid>", "linkedInPageId": "87654321",
//     "label": "Alice's Studio", "logoUrl": "…" }
//
// The model shipped with only `personal` / `org`, so a real `orgPage` row fell
// through to the unknown-token case and its page identity (`pageId`,
// `linkedInPageId`) and logo were dropped entirely. That matters beyond
// cosmetics: an org page assignment silently redirects a member's ordinary
// LinkedIn cross-post to the company page, so a client that cannot see the
// `orgPage` kind will tell the user they are posting to their own profile
// while the server publishes to a company page.
//
// `orgScopeMissing` is true when the user has a LinkedIn connection whose
// stored scope lacks `rw_organization_admin`.

/// A LinkedIn posting target the user can cross-post to.
public struct LinkedInTargetDTO: Decodable, Sendable, Equatable {
    public let kind: String
    public let label: String
    /// Personal-profile avatar. Only the `personal` kind carries this.
    public let avatarUrl: String?
    /// Present on `posting-targets` (whether the target is currently enabled).
    public let enabled: Bool?

    /// `OrgLinkedInPage` record id — present on the `orgPage` kind. This is
    /// the id that goes in a message's `linkedInTargets`.
    public let pageId: String?
    /// `LinkedInPersonalPage` record id — present on the `personalPage` kind.
    public let personalPageId: String?
    /// LinkedIn's own page identifier, on either page kind.
    public let linkedInPageId: String?
    /// Page logo, on either page kind (pages use `logoUrl`, not `avatarUrl`).
    public let logoUrl: String?

    public init(
        kind: String,
        label: String,
        avatarUrl: String? = nil,
        enabled: Bool? = nil,
        pageId: String? = nil,
        personalPageId: String? = nil,
        linkedInPageId: String? = nil,
        logoUrl: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.avatarUrl = avatarUrl
        self.enabled = enabled
        self.pageId = pageId
        self.personalPageId = personalPageId
        self.linkedInPageId = linkedInPageId
        self.logoUrl = logoUrl
    }
}

/// `GET /api/linkedin/posting-targets` response.
public struct LinkedInPostingTargetsResponse: Decodable, Sendable, Equatable {
    public let targets: [LinkedInTargetDTO]
    /// `true` when the LinkedIn connection's stored scope lacks
    /// `rw_organization_admin`, so page targets are unavailable. The fix is to
    /// reconnect via `GET /api/auth/linkedin/authorize?link=true`.
    public let orgScopeMissing: Bool?

    public init(targets: [LinkedInTargetDTO], orgScopeMissing: Bool? = nil) {
        self.targets = targets
        self.orgScopeMissing = orgScopeMissing
    }
}
