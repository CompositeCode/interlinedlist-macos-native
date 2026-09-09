import Foundation
import InterlinedKit

// MARK: - Organizations DTO → domain mapping
//
// Per-group slice of the audit-in-one-place mapper convention (PLAN.md §3).
// The Organizations surface ships in M6 (PLAN.md §6 M6 — "Subscriber & orgs").
// Per decision 0003 the App layer never references the kit DTOs — `OrgService`
// returns `Organization` / `OrgMember` / `OrgUser` values, and this file is
// the one place that crosses the boundary.

extension Organization {

    /// Maps the org DTO to the domain value. `isPublic` is optional on the
    /// wire; absence is treated as private (`false`) — the conservative
    /// default for a not-explicitly-public org.
    public init(from dto: OrganizationDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            description: dto.description,
            isPublic: dto.isPublic ?? false,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            slug: dto.slug,
            // A missing `isSystem` means "ordinary org". Defaulting the other
            // way would make an org un-leavable on a lean response.
            isSystem: dto.isSystem ?? false,
            memberCount: dto.memberCount
        )
    }

    /// The caller's role in this org, when the row carries one. The live
    /// collection routes emit `role` and `userRole` with the same value;
    /// either is accepted so a route that sends only one still resolves.
    public static func callerRole(from dto: OrganizationDTO) -> OrgRole? {
        guard let token = dto.role ?? dto.userRole else { return nil }
        return OrgRole(wireToken: token)
    }
}

extension OrgsPage {

    /// Maps a paginated org envelope to the domain page. `nextOffset` is
    /// derived from `offset + limit` when `hasMore`, matching `TimelinePage`
    /// / `OwnedListsPage`.
    public init(from paginated: Paginated<OrganizationDTO>) {
        let info = paginated.pagination
        self.init(
            organizations: paginated.items.map(Organization.init(from:)),
            hasMore: info.hasMore,
            nextOffset: info.hasMore ? info.offset + info.limit : nil
        )
    }
}

extension OrgMember {

    /// Maps a member listing row (no membership-record id on this shape).
    /// Carries the identity fields the live listing denormalizes onto the row,
    /// so the roster renders names and avatars without a second lookup.
    public init(from dto: OrganizationMemberDTO) {
        self.init(
            userId: dto.userId,
            membershipId: nil,
            role: OrgRole(wireToken: dto.role),
            active: dto.active,
            createdAt: dto.createdAt,
            username: dto.username,
            displayName: dto.displayName,
            // The live rows use "" for "no avatar", not null — treat a blank
            // string as absent so the UI falls back to its placeholder.
            avatarURL: dto.avatar
                .flatMap { $0.isEmpty ? nil : $0 }
                .flatMap(URL.init(string:)),
            emailVerified: dto.emailVerified
        )
    }

    /// Maps the nested membership object the server returns on the
    /// `POST` / `PUT` member-mutation responses — this shape carries the
    /// membership record id.
    public init(from dto: OrganizationMembershipDTO) {
        self.init(
            userId: dto.userId,
            membershipId: dto.id,
            role: OrgRole(wireToken: dto.role),
            active: dto.active,
            createdAt: dto.createdAt
        )
    }
}

extension OrgMembersPage {

    /// Maps a paginated members envelope to the domain page.
    public init(from paginated: Paginated<OrganizationMemberDTO>) {
        let info = paginated.pagination
        self.init(
            members: paginated.items.map(OrgMember.init(from:)),
            hasMore: info.hasMore,
            nextOffset: info.hasMore ? info.offset + info.limit : nil
        )
    }
}

extension OrgUser {

    /// Maps a user-with-role row. The DTO's user fields are all optional
    /// (the canonical user model is owned by another kit group, so this row
    /// is deliberately tolerant): `username` / `displayName` fall back so the
    /// UI always has something to render, and `role` falls back to
    /// `.other("")` when the server omits it.
    public init(from dto: OrganizationUserDTO) {
        let username = dto.username ?? dto.id
        let displayName = dto.displayName ?? username
        let summary = UserSummary(
            id: dto.id,
            username: username,
            displayName: displayName,
            avatarURL: dto.avatarUrl.flatMap(URL.init(string:))
        )
        self.init(
            summary: summary,
            role: OrgRole(wireToken: dto.role ?? "")
        )
    }
}
