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

    /// A Mastodon instance.
    ///
    /// The instance host is carried on ``LinkedIdentity/instance``, not in this
    /// case — one `.mastodon` provider, many linked instances. Modelling the
    /// host in the enum would make every instance its own provider and every
    /// `switch` over providers unbounded.
    case mastodon

    /// X (formerly Twitter).
    ///
    /// Was absent from this enum entirely, so a linked X identity — which the
    /// test account has, and which cross-posting to X depends on — decoded as
    /// `.other("twitter")` and rendered as an unknown provider (GitHub #47).
    case twitter

    /// Bluesky / AT Protocol.
    case bluesky

    /// LinkedIn.
    case linkedin

    /// A provider token the client does not yet recognise. Preserved for
    /// display; the App layer renders a generic provider label.
    case other(String)

    /// Maps a wire string to a provider, case-insensitively. Unknown tokens
    /// preserve their original casing under `.other`.
    ///
    /// **Mastodon arrives instance-qualified.** The live payload sends
    /// `"mastodon:techhub.social"`, not `"mastodon"` — confirmed 2026-09-15:
    ///
    /// ```json
    /// {"provider":"mastodon:techhub.social",
    ///  "providerUsername":"interlinedlist_crew@techhub.social"}
    /// ```
    ///
    /// An exact match on `"mastodon"` therefore sent **every** Mastodon
    /// identity to `.other`, where the UI renders it as an unknown provider and
    /// offers none of its actions (GitHub #47). The prefix is split here, in the
    /// one place that reads the token, and the host is returned by
    /// ``instanceHost(fromWireToken:)`` for the caller to carry.
    public init(wireToken: String) {
        let lowered = wireToken.lowercased()
        if lowered == "mastodon" || lowered.hasPrefix("mastodon:") {
            self = .mastodon
            return
        }
        switch lowered {
        case "github":   self = .github
        case "bluesky", "atproto": self = .bluesky
        case "linkedin": self = .linkedin
        case "twitter", "x": self = .twitter
        default:         self = .other(wireToken)
        }
    }

    /// The instance host embedded in a provider token, when there is one.
    ///
    /// `"mastodon:techhub.social"` → `"techhub.social"`; everything else `nil`.
    /// Separate from `init(wireToken:)` because the provider and the instance
    /// are two facts encoded in one string, and a caller usually wants both.
    public static func instanceHost(fromWireToken token: String) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].lowercased() == "mastodon" else { return nil }
        let host = String(parts[1])
        return host.isEmpty ? nil : host
    }

    /// The canonical wire token for this provider.
    public var wireToken: String {
        switch self {
        case .github:   return "github"
        case .mastodon: return "mastodon"
        case .bluesky:  return "bluesky"
        case .linkedin: return "linkedin"
        case .twitter:  return "twitter"
        case .other(let raw): return raw
        }
    }

    /// The label the UI shows.
    ///
    /// `.other` surfaces its raw token capitalised, so an unrecognised provider
    /// still renders a legible name — and an *empty* token falls back to
    /// "Account" rather than rendering a blank row, which would look like a
    /// layout bug rather than an unknown provider.
    ///
    /// Note `.twitter` reads "X" while its wire token stays `"twitter"`: the
    /// server's vocabulary and the user's are different, and this is the seam
    /// between them.
    public var displayName: String {
        switch self {
        case .github:   return "GitHub"
        case .mastodon: return "Mastodon"
        case .bluesky:  return "Bluesky"
        case .linkedin: return "LinkedIn"
        case .twitter:  return "X"
        case .other(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Account" : trimmed.capitalized
        }
    }

    // MARK: - Per-provider capability
    //
    // Data, not a switch statement per call site (GitHub #47). The Integrations
    // pane renders one row per provider and needs to know which actions that row
    // offers; expressing it here keeps the view a projection of the model rather
    // than a parallel copy of these rules.

    /// Whether the provider supports more than one linked account.
    ///
    /// Only Mastodon does, which is why it is the one that will not retrofit if
    /// it is modelled as a scalar first.
    public var supportsMultipleInstances: Bool { self == .mastodon }

    /// Whether linking needs an instance host from the user before an authorize
    /// URL can even be built.
    public var requiresInstanceHost: Bool { self == .mastodon }

    /// Whether `POST /api/user/identities/verify` is meaningful for this
    /// provider. `.other` is excluded: the client cannot describe what it would
    /// be verifying.
    public var isVerifiable: Bool {
        if case .other = self { return false }
        return true
    }

    /// Whether the provider can be disconnected from this client.
    public var isDisconnectable: Bool {
        if case .other = self { return false }
        return true
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

    /// The Mastodon instance host this identity lives on, e.g.
    /// `"techhub.social"`. `nil` for every other provider.
    ///
    /// Split out of the provider token, which arrives as
    /// `"mastodon:techhub.social"`. Carried here rather than in the provider
    /// enum because an account can link several instances, and one `.mastodon`
    /// case with a host per identity is the shape that supports that; a case per
    /// host would make the enum unbounded.
    public let instance: String?

    /// The token the *server* uses for this identity, which for Mastodon is
    /// instance-qualified.
    ///
    /// Unlink and verify both address an identity by provider token, so a
    /// Mastodon call that sent a bare `"mastodon"` would be ambiguous on an
    /// account with two instances — and the server could disconnect the wrong
    /// one. This is the value those calls must send.
    public var providerWireToken: String {
        guard provider == .mastodon, let instance, !instance.isEmpty else {
            return provider.wireToken
        }
        return "mastodon:\(instance)"
    }

    public init(
        id: String,
        provider: IdentityProvider,
        handle: String? = nil,
        profileURL: URL? = nil,
        avatarURL: URL? = nil,
        connectedAt: Date? = nil,
        lastVerifiedAt: Date? = nil,
        instance: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.handle = handle
        self.profileURL = profileURL
        self.avatarURL = avatarURL
        self.connectedAt = connectedAt
        self.lastVerifiedAt = lastVerifiedAt
        self.instance = instance
    }
}

// MARK: - UserOrganization

/// An organization the signed-in user belongs to, with their membership
/// metadata, as `GET /api/user/organizations` returns it (PLAN.md §1
/// "Organizations" / org switcher, §6 M6).
///
/// Distinct from `Organization`: this is the *membership view* (the org plus
/// the caller's own `role` and `joinedAt`), surfaced from the
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

    /// Whether the caller may leave this org **on the client's own rules**,
    /// before any network call. Two rules from `/help/organizations`:
    ///
    /// - nobody can leave the system org ("The Public"); and
    /// - the last remaining owner cannot leave until another owner exists.
    ///
    /// The second rule needs the org's owner count, which this row does not
    /// carry — so it is enforced by `OrgLifecycleError.lastOwnerCannotLeave`
    /// at the service seam, where the roster is available. This property
    /// answers only the part the row can decide by itself.
    public var isLeavable: Bool { !organization.isSystem }

    public init(organization: Organization, role: OrgRole, joinedAt: Date? = nil) {
        self.organization = organization
        self.role = role
        self.joinedAt = joinedAt
    }
}

// MARK: - GitHubConnection

/// The GitHub side of the Integrations pane (GitHub #47 / G33).
///
/// Separate from `LinkedIdentity` because it describes the **app's** GitHub
/// configuration rather than one user's link: `isConfigured == false` means no
/// amount of user action will make linking work, which is a different message
/// from "you have not linked GitHub".
public struct GitHubConnection: Sendable, Equatable {

    /// Whether GitHub OAuth is configured on the server at all.
    public let isConfigured: Bool

    /// The github.com page that manages this app's organization access — the
    /// "Update orgs" destination.
    ///
    /// Opened in the browser on purpose: it is GitHub's own consent UI, and
    /// re-implementing it natively would mean maintaining a copy of someone
    /// else's permissions screen.
    public let manageOrgAccessURL: URL?

    public init(isConfigured: Bool, manageOrgAccessURL: URL? = nil) {
        self.isConfigured = isConfigured
        self.manageOrgAccessURL = manageOrgAccessURL
    }
}
