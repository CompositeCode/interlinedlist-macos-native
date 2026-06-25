import Foundation

// MARK: - IdentityProvider

/// An OAuth provider a user can link their account to (PLAN.md §1 "Profile &
/// account / linked identities", §6 M6 — "OAuth identity linking").
///
/// The wire format encodes the provider as a free-form string
/// (`LinkedIdentityDTO.provider`). The domain layer maps the providers the
/// app knows to typed cases and preserves any unrecognised wire string under
/// `.other(String)` so a newly-added provider still renders rather than
/// crashing a switch — the same forward-compatible pattern as `WatcherRole`,
/// `NotificationKind`, and `OrgRole`.
public enum IdentityProvider: Sendable, Equatable, Hashable {

    /// GitHub.
    case github

    /// A Mastodon instance (the specific instance host is carried on the
    /// `LinkedIdentity`, not the provider case).
    case mastodon

    /// Bluesky / AT Protocol.
    case bluesky

    /// LinkedIn.
    case linkedin

    /// A provider token the client does not yet recognise. Preserved for
    /// display; the App layer renders a generic provider label.
    case other(String)

    /// Maps a wire string to a provider, case-insensitively. Unknown tokens
    /// preserve their original casing under `.other`.
    public init(wireToken: String) {
        switch wireToken.lowercased() {
        case "github":   self = .github
        case "mastodon": self = .mastodon
        case "bluesky", "atproto": self = .bluesky
        case "linkedin": self = .linkedin
        default:         self = .other(wireToken)
        }
    }

    /// The canonical wire token for this provider.
    public var wireToken: String {
        switch self {
        case .github:   return "github"
        case .mastodon: return "mastodon"
        case .bluesky:  return "bluesky"
        case .linkedin: return "linkedin"
        case .other(let raw): return raw
        }
    }
}

// MARK: - LinkedIdentity

/// A single linked OAuth identity on the signed-in account, as the Settings >
/// Identities UI renders it (PLAN.md §1 "Profile & account", §6 M6).
///
/// Domain projection of `InterlinedKit.LinkedIdentityDTO`. Per decision 0003
/// the DTO never crosses into the UI — `UserService.identities()` returns
/// `[LinkedIdentity]` and `IdentityMappers` is the one place that crosses the
/// boundary.
public struct LinkedIdentity: Sendable, Equatable, Hashable, Identifiable {

    /// The identity record id (server-assigned). Identity for `Identifiable`.
    public let id: String

    /// The provider this identity belongs to.
    public let provider: IdentityProvider

    /// The username / handle on the provider (e.g. the GitHub login, the
    /// `@user@instance` Mastodon handle). `nil` when the server omits it.
    public let handle: String?

    /// The public profile URL on the provider, when available.
    public let profileURL: URL?

    /// The provider avatar URL, when available.
    public let avatarURL: URL?

    /// When the identity was linked. `nil` when the server omits it.
    public let connectedAt: Date?

    /// When the link was last verified. `nil` when the server omits it.
    public let lastVerifiedAt: Date?

    public init(
        id: String,
        provider: IdentityProvider,
        handle: String? = nil,
        profileURL: URL? = nil,
        avatarURL: URL? = nil,
        connectedAt: Date? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.handle = handle
        self.profileURL = profileURL
        self.avatarURL = avatarURL
        self.connectedAt = connectedAt
        self.lastVerifiedAt = lastVerifiedAt
    }
}

// MARK: - UserOrganization

/// An organization the signed-in user belongs to, with their membership
/// metadata, as `GET /api/user/organizations` returns it (PLAN.md §1
/// "Organizations" / org switcher, §6 M6).
///
/// Distinct from `Organization`: this is the *membership view* (the org plus
/// the caller's own `role` and `joinedAt`), surfaced from the session-only
/// `/api/user/organizations` endpoint. Domain projection of
/// `InterlinedKit.UserOrganizationDTO`.
public struct UserOrganization: Sendable, Equatable, Hashable, Identifiable {

    /// The org these membership fields describe.
    public let organization: Organization

    /// The caller's role in this org.
    public let role: OrgRole

    /// When the caller joined this org. `nil` when the server omits it.
    public let joinedAt: Date?

    public var id: String { organization.id }

    public init(organization: Organization, role: OrgRole, joinedAt: Date? = nil) {
        self.organization = organization
        self.role = role
        self.joinedAt = joinedAt
    }
}
