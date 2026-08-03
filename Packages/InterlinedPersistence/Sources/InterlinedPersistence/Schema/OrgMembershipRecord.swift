import Foundation
import SwiftData

/// SwiftData record for a cached `UserOrganization` — the caller's own
/// membership in an org (PLAN.md §1 "Organizations", §5 stale-while-revalidate,
/// §6 M6 — org switcher). Distinct from `OrgRecord` / `OrgMemberRecord`, which
/// cache the org-management surface (an org and *its* member roster); this row
/// caches the initial-view data the Organizations sidebar / switcher paints:
/// one row per org the signed-in user belongs to, denormalized with the org's
/// display fields plus the caller's own role and joined-at.
///
/// The org fields are denormalized onto the row (rather than modelling a
/// relationship to `OrgRecord`) so the switcher can render on first paint from
/// a single flat fetch — the same denormalize-for-first-paint choice
/// `MessageRecord` makes for the author identity.
///
/// A `position` column preserves the API's returned order so the cached
/// switcher renders identically online and offline; `cacheMemberships`
/// replaces the whole set (page semantics), so removed memberships disappear.
///
/// `OrgRole` is persisted as its `wireToken` (`roleRaw`) and rehydrated via
/// `OrgRole(wireToken:)`, so an unrecognised `.other("foo")` token round-trips
/// losslessly and a future typed-case promotion is a domain-only change —
/// matching `OrgMemberRecord.roleRaw`.
///
/// Internal to the package: `SwiftDataOrgStore` consumers only see the
/// `UserOrganization` value type across the actor boundary; the `@Model`
/// records never escape.
@Model
final class OrgMembershipRecord {

    /// The org id — one membership row per org for the caller.
    @Attribute(.unique) var orgID: String

    // Denormalized organization display fields.
    var name: String
    var orgDescription: String?
    var isPublic: Bool
    var orgCreatedAt: Date?
    var orgUpdatedAt: Date?

    /// Wire string for the caller's role. Rehydrated via `OrgRole(wireToken:)`.
    var roleRaw: String

    /// When the caller joined this org. `nil` when the server omits it.
    var joinedAt: Date?

    /// The API's returned position, preserved for a stable switcher order.
    var position: Int

    init(
        orgID: String,
        name: String,
        orgDescription: String? = nil,
        isPublic: Bool = false,
        orgCreatedAt: Date? = nil,
        orgUpdatedAt: Date? = nil,
        roleRaw: String,
        joinedAt: Date? = nil,
        position: Int
    ) {
        self.orgID = orgID
        self.name = name
        self.orgDescription = orgDescription
        self.isPublic = isPublic
        self.orgCreatedAt = orgCreatedAt
        self.orgUpdatedAt = orgUpdatedAt
        self.roleRaw = roleRaw
        self.joinedAt = joinedAt
        self.position = position
    }
}
