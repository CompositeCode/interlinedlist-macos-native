import Foundation
import SwiftData

/// SwiftData record for a cached `Organization` (PLAN.md §1 "Organizations",
/// §5 stale-while-revalidate, §6 M6 — org switcher + member management).
///
/// One row per org id. Mirrors the round-trip surface of
/// `InterlinedDomain.Organization` so the org switcher and management UI can
/// paint instantly from the cache before the network refresh lands.
///
/// Internal to the package: `SwiftDataOrgStore` consumers only see
/// `Organization` / `OrgMember` value types across the actor boundary; the
/// `@Model` records never escape.
@Model
final class OrgRecord {

    @Attribute(.unique) var id: String

    var name: String
    var orgDescription: String?
    var isPublic: Bool
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: String,
        name: String,
        orgDescription: String? = nil,
        isPublic: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.orgDescription = orgDescription
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - OrgMemberRecord

/// SwiftData record for a cached `OrgMember` (PLAN.md §6 M6).
///
/// Member rows relate to their org through a flat `orgID` discriminator
/// rather than a SwiftData relationship — the same shape `ListRowRecord`
/// (`listID`) and `ListWatcherRecord` (`listID`) use to key child rows by
/// their parent in this package, and the same flat per-entity keying
/// `FollowCountsRecord` (`userID`) uses. This keeps per-org isolation a
/// simple `#Predicate { $0.orgID == orgID }` fetch and avoids the
/// migration / cascade cost of a modelled relationship for a cache that is
/// cleared wholesale on sign-out.
///
/// The composite identity is (`orgID`, `userId`) — a user is a member of an
/// org at most once. SwiftData has no compound `@Attribute(.unique)`, so the
/// uniqueness is enforced in the store's upsert (fetch-by-pair then update or
/// insert), matching how the package's other child rows handle it.
///
/// `OrgRole` is persisted as its `wireToken` string (`roleRaw`) and
/// rehydrated via `OrgRole(wireToken:)`, so promoting a `.other("foo")`
/// token to a typed case is a domain-only change with no on-disk migration —
/// the same forward-compatible pattern `NotificationRecord.kindRaw` uses.
@Model
final class OrgMemberRecord {

    /// The org this membership belongs to (flat foreign key).
    var orgID: String

    /// The member user's id.
    var userId: String

    /// The membership record id, when the server returned it.
    var membershipId: String?

    /// Wire string for the role. Rehydrated via `OrgRole(wireToken:)`.
    var roleRaw: String

    /// Whether the membership is active. `nil` when the server omits it.
    var active: Bool?

    var createdAt: Date?

    init(
        orgID: String,
        userId: String,
        membershipId: String? = nil,
        roleRaw: String,
        active: Bool? = nil,
        createdAt: Date? = nil
    ) {
        self.orgID = orgID
        self.userId = userId
        self.membershipId = membershipId
        self.roleRaw = roleRaw
        self.active = active
        self.createdAt = createdAt
    }
}
