import Foundation

// MARK: - LinkedIn posting-target DTOs (work-consolidation.md G11a)
//
// Shapes verified live 2026-07-31 (read-only):
//   GET /api/linkedin/posting-targets
//       -> { targets: [{ kind, label, avatarUrl, enabled }], orgScopeMissing }
//   GET /api/linkedin/targets
//       -> { targets: [{ kind, label, avatarUrl }] }
//
// `kind` is "personal" or "org". Org targets require the LinkedIn org scope,
// which is not enabled for every tenant (`orgScopeMissing` / status
// `orgScopesEnabled:false`) — the org half is tracked separately as G11b.

/// A LinkedIn posting target the user can cross-post to.
public struct LinkedInTargetDTO: Decodable, Sendable, Equatable {
    public let kind: String
    public let label: String
    public let avatarUrl: String?
    /// Present on `posting-targets` (whether the target is currently enabled).
    public let enabled: Bool?

    public init(kind: String, label: String, avatarUrl: String? = nil, enabled: Bool? = nil) {
        self.kind = kind
        self.label = label
        self.avatarUrl = avatarUrl
        self.enabled = enabled
    }
}

/// `GET /api/linkedin/posting-targets` response.
public struct LinkedInPostingTargetsResponse: Decodable, Sendable, Equatable {
    public let targets: [LinkedInTargetDTO]
    /// `true` when the LinkedIn org scope is not granted, so org page targets
    /// are unavailable (G11b — deferred).
    public let orgScopeMissing: Bool?

    public init(targets: [LinkedInTargetDTO], orgScopeMissing: Bool? = nil) {
        self.targets = targets
        self.orgScopeMissing = orgScopeMissing
    }
}
