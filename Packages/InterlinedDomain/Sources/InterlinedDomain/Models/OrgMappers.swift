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
            updatedAt: dto.updatedAt
        )
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

    /// Maps a member listing row (keyed by `userId`, no membership-record id).
    public init(from dto: OrganizationMemberDTO) {
        self.init(
            userId: dto.userId,
            membershipId: nil,
            role: OrgRole(wireToken: dto.role),
            active: dto.active,
            createdAt: dto.createdAt
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
