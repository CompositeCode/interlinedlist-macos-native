import Foundation
import InterlinedDomain

/// Internal mapping between the SwiftData `OrgMembershipRecord` and the domain
/// `UserOrganization` value type. Mirrors the `OrgRecordMapping` pattern —
/// `@Model` instances stay inside the actor; only `Sendable` value types cross
/// the boundary (required under Swift 6 strict concurrency).
///
/// The record denormalizes the nested `Organization` fields; this mapping is
/// the one place that folds them back into a `UserOrganization`. `OrgRole` is
/// persisted as its `wireToken` and rehydrated via `OrgRole(wireToken:)`, so a
/// `.other("foo")` token round-trips losslessly.

extension OrgMembershipRecord {

    /// Build a new record from a domain `UserOrganization`, tagged with its
    /// position in the returned list (for a stable read order).
    convenience init(from membership: UserOrganization, position: Int) {
        self.init(
            orgID: membership.organization.id,
            name: membership.organization.name,
            orgDescription: membership.organization.description,
            isPublic: membership.organization.isPublic,
            orgCreatedAt: membership.organization.createdAt,
            orgUpdatedAt: membership.organization.updatedAt,
            roleRaw: membership.role.wireToken,
            joinedAt: membership.joinedAt,
            position: position
        )
    }

    /// Hydrate the row into a domain `UserOrganization` value.
    func toUserOrganization() -> UserOrganization {
        UserOrganization(
            organization: Organization(
                id: orgID,
                name: name,
                description: orgDescription,
                isPublic: isPublic,
                createdAt: orgCreatedAt,
                updatedAt: orgUpdatedAt
            ),
            role: OrgRole(wireToken: roleRaw),
            joinedAt: joinedAt
        )
    }
}
