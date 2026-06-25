import Foundation

// MARK: - OrgRole

/// Role granted to a member of an organization (PLAN.md §1 "Organizations",
/// §6 M6 — "member management with roles (owner/admin/member)").
///
/// The wire format encodes the role as a free-form string
/// (`OrganizationMemberDTO.role`). The documented taxonomy is
/// `owner | admin | member`; the domain layer maps those to typed cases and
/// preserves any unrecognised wire string under `.other(String)` so an
/// unexpected role round-trips through the UI rather than crashing a switch.
///
/// This mirrors the forward-compatible `WatcherRole.other(String)` pattern
/// introduced in Wave 4 and the `NotificationKind.other(String)` pattern from
/// Wave 6.
public enum OrgRole: Sendable, Equatable, Hashable {

    /// Full control: manage the org, manage members and their roles, delete
    /// the org.
    case owner

    /// Administrative access: manage members and most org settings; cannot
    /// delete the org (by the working taxonomy).
    case admin

    /// Standard membership: belongs to the org with no management rights.
    case member

    /// A role token the client does not yet recognise. Treated as the
    /// least-privileged role for any client-side gating; preserved for display.
    case other(String)

    /// Maps a wire string to a role, case-insensitively. Unknown tokens
    /// preserve their original casing under `.other`.
    public init(wireToken: String) {
        switch wireToken.lowercased() {
        case "owner": self = .owner
        case "admin", "administrator": self = .admin
        case "member": self = .member
        default: self = .other(wireToken)
        }
    }

    /// The canonical wire token for this role — used when sending a role to
    /// the server (add member, update member role).
    public var wireToken: String {
        switch self {
        case .owner: return "owner"
        case .admin: return "admin"
        case .member: return "member"
        case .other(let raw): return raw
        }
    }
}

// MARK: - Organization

/// An organization the app renders in the org switcher and management UI
/// (PLAN.md §1 "Organizations", §6 M6).
///
/// Domain projection of `InterlinedKit.OrganizationDTO`. Per decision 0003 the
/// DTO never crosses into the UI — `OrgService` returns `Organization` values
/// and `OrgMappers` is the one place that crosses the boundary.
public struct Organization: Sendable, Equatable, Hashable, Identifiable {

    public let id: String
    public let name: String
    public let description: String?
    /// Whether the org is publicly listed. The wire field is optional; this
    /// defaults to `false` (private) when the server omits it.
    public let isPublic: Bool
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        isPublic: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - OrgMember

/// A membership row from `GET /api/organizations/[id]/members` and the
/// `POST` / `PUT` member-mutation responses (PLAN.md §6 M6).
///
/// Domain projection of `InterlinedKit.OrganizationMemberDTO` /
/// `OrganizationMembershipDTO`. The `membershipId` is the server's id for the
/// membership *record* — present on the `POST` / `PUT` envelope (which nests
/// the full membership) and `nil` on the bare members listing (which keys by
/// `userId`).
public struct OrgMember: Sendable, Equatable, Hashable, Identifiable {

    /// The member user's id. Identity for `Identifiable` (a user is a member
    /// of an org at most once).
    public let userId: String

    /// The membership record id, when the server returned it (the
    /// `POST` / `PUT` envelope carries it; the listing does not).
    public let membershipId: String?

    /// The member's role in the org.
    public let role: OrgRole

    /// Whether the membership is active. `nil` when the server omits the flag.
    public let active: Bool?

    /// When the membership was created, when the server includes the timestamp.
    public let createdAt: Date?

    public var id: String { userId }

    public init(
        userId: String,
        membershipId: String? = nil,
        role: OrgRole,
        active: Bool? = nil,
        createdAt: Date? = nil
    ) {
        self.userId = userId
        self.membershipId = membershipId
        self.role = role
        self.active = active
        self.createdAt = createdAt
    }
}

// MARK: - OrgUser

/// A user-with-role row from `GET /api/organizations/[id]/users` (PLAN.md
/// §6 M6). Carries the user's identity alongside their org role so the member
/// management UI can render a roster without a second user lookup.
///
/// Domain projection of `InterlinedKit.OrganizationUserDTO`. Reuses
/// `UserSummary` for the identity so avatar handling and display-name fallback
/// stay in one place across the app.
public struct OrgUser: Sendable, Equatable, Hashable, Identifiable {

    /// The user's identity (id, username, display name, avatar).
    public let summary: UserSummary

    /// The user's role in the org. `.other("")` when the server omitted the
    /// role on this row.
    public let role: OrgRole

    public var id: String { summary.id }

    public init(summary: UserSummary, role: OrgRole) {
        self.summary = summary
        self.role = role
    }
}

// MARK: - OrgsPage

/// One page of organizations — the same `*Page` shape every paginated read in
/// the domain layer uses (`TimelinePage`, `OwnedListsPage`, `UsersPage`).
public struct OrgsPage: Sendable, Equatable {

    public let organizations: [Organization]
    public let hasMore: Bool
    public let nextOffset: Int?

    public init(organizations: [Organization], hasMore: Bool, nextOffset: Int?) {
        self.organizations = organizations
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// The empty-page boundary value — used when the account has no orgs.
    public static let empty = OrgsPage(organizations: [], hasMore: false, nextOffset: nil)
}

// MARK: - OrgMembersPage

/// One page of org members — same `*Page` shape as `OrgsPage`.
public struct OrgMembersPage: Sendable, Equatable {

    public let members: [OrgMember]
    public let hasMore: Bool
    public let nextOffset: Int?

    public init(members: [OrgMember], hasMore: Bool, nextOffset: Int?) {
        self.members = members
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// The empty-page boundary value — an org with no members on this page.
    public static let empty = OrgMembersPage(members: [], hasMore: false, nextOffset: nil)
}
