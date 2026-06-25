import Foundation
import InterlinedKit

// MARK: - User identities + organizations DTO → domain mapping
//
// Per-group slice of the audit-in-one-place mapper convention (PLAN.md §3).
// Backs `UserService` (PLAN.md §6 M6 — "OAuth identity linking",
// "Organizations" / org switcher). Per decision 0003 the App layer never
// references the kit DTOs — `UserService` returns `LinkedIdentity` /
// `UserOrganization` values, and this file is the one place that crosses the
// boundary.

extension LinkedIdentity {

    /// Maps a linked-identity DTO to the domain value. The provider string is
    /// narrowed to `IdentityProvider`; URL strings are parsed into `URL?`
    /// here so the view layer never deals with raw, possibly-malformed
    /// strings.
    public init(from dto: LinkedIdentityDTO) {
        self.init(
            id: dto.id,
            provider: IdentityProvider(wireToken: dto.provider),
            handle: dto.providerUsername,
            profileURL: dto.profileUrl.flatMap(URL.init(string:)),
            avatarURL: dto.avatarUrl.flatMap(URL.init(string:)),
            connectedAt: dto.connectedAt,
            lastVerifiedAt: dto.lastVerifiedAt
        )
    }
}

extension UserOrganization {

    /// Maps a `UserOrganizationDTO` (the membership-view row) to the domain
    /// value. The org fields project into a nested `Organization`; the
    /// caller's `role` is narrowed to `OrgRole`. `isPublic` defaults to
    /// `false` (private) when the server omits it, matching
    /// `Organization.init(from: OrganizationDTO)`.
    public init(from dto: UserOrganizationDTO) {
        let organization = Organization(
            id: dto.id,
            name: dto.name,
            description: dto.description,
            isPublic: dto.isPublic ?? false,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
        self.init(
            organization: organization,
            role: OrgRole(wireToken: dto.role),
            joinedAt: dto.joinedAt
        )
    }
}
