import Foundation
import InterlinedDomain

/// Internal mapping between the SwiftData org records (`OrgRecord`,
/// `OrgMemberRecord`) and the domain value types (`Organization`,
/// `OrgMember`). Mirrors the `NotificationRecordMapping` / `ListRecordMapping`
/// pattern from earlier waves — `@Model` instances stay inside the actor;
/// only `Sendable` value types cross the boundary (required under Swift 6
/// strict concurrency).
///
/// `OrgRole` is persisted as its `wireToken` and rehydrated via
/// `OrgRole(wireToken:)`, so a `.other("foo")` token round-trips losslessly
/// and a future typed-case promotion is a domain-only change.

extension OrgRecord {

    /// Build a new record from a domain `Organization`.
    convenience init(from organization: Organization) {
        self.init(
            id: organization.id,
            name: organization.name,
            orgDescription: organization.description,
            isPublic: organization.isPublic,
            createdAt: organization.createdAt,
            updatedAt: organization.updatedAt
        )
    }

    /// Copy fresh field values from a domain `Organization` into an existing
    /// managed record — the upsert path. Every mutable field is touched so
    /// stale state cannot leak through.
    func apply(_ organization: Organization) {
        // `id` is the primary key.
        name = organization.name
        orgDescription = organization.description
        isPublic = organization.isPublic
        createdAt = organization.createdAt
        updatedAt = organization.updatedAt
    }

    /// Hydrate the row into a domain `Organization` value.
    func toOrganization() -> Organization {
        Organization(
            id: id,
            name: name,
            description: orgDescription,
            isPublic: isPublic,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension OrgMemberRecord {

    /// Build a new record from a domain `OrgMember`, tagged with its org id.
    convenience init(from member: OrgMember, orgID: String) {
        self.init(
            orgID: orgID,
            userId: member.userId,
            membershipId: member.membershipId,
            roleRaw: member.role.wireToken,
            active: member.active,
            createdAt: member.createdAt
        )
    }

    /// Copy fresh field values from a domain `OrgMember` into an existing
    /// managed record — the upsert path. `orgID` and `userId` are the
    /// composite identity and stay put.
    func apply(_ member: OrgMember) {
        membershipId = member.membershipId
        roleRaw = member.role.wireToken
        active = member.active
        createdAt = member.createdAt
    }

    /// Hydrate the row into a domain `OrgMember` value.
    func toOrgMember() -> OrgMember {
        OrgMember(
            userId: userId,
            membershipId: membershipId,
            role: OrgRole(wireToken: roleRaw),
            active: active,
            createdAt: createdAt
        )
    }
}
