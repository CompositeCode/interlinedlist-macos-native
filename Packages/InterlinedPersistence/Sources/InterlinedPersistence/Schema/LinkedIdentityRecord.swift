import Foundation
import SwiftData

/// SwiftData record for a cached `LinkedIdentity` (PLAN.md §1 "Profile &
/// account / linked identities", §5 stale-while-revalidate, §6 M6 — OAuth
/// identity linking).
///
/// One row per identity record id. The Settings > Identities screen renders
/// off this cache so the linked-account list paints instantly before the
/// network refresh lands. The list is a single-user cache (the signed-in
/// account's identities); `SwiftDataLinkedIdentityStore` clears and rewrites
/// it wholesale on each refresh, so there is no per-user discriminator here.
///
/// `IdentityProvider` is persisted as its `wireToken` string (`providerRaw`)
/// and rehydrated via `IdentityProvider(wireToken:)` — the same
/// forward-compatible pattern as `OrgRole` / `NotificationKind`, so a
/// newly-added provider needs no on-disk migration. URLs are stored as their
/// absolute strings (`profileURLString`, `avatarURLString`), matching the
/// `NotificationRecord.actorAvatarURLString` convention.
///
/// Internal to the package: consumers see only `LinkedIdentity` values
/// across the actor boundary; the `@Model` record never escapes.
@Model
final class LinkedIdentityRecord {

    @Attribute(.unique) var id: String

    /// Wire string for the provider. Rehydrated via `IdentityProvider(wireToken:)`.
    var providerRaw: String

    var handle: String?
    var profileURLString: String?
    var avatarURLString: String?
    var connectedAt: Date?
    var lastVerifiedAt: Date?

    init(
        id: String,
        providerRaw: String,
        handle: String? = nil,
        profileURLString: String? = nil,
        avatarURLString: String? = nil,
        connectedAt: Date? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.providerRaw = providerRaw
        self.handle = handle
        self.profileURLString = profileURLString
        self.avatarURLString = avatarURLString
        self.connectedAt = connectedAt
        self.lastVerifiedAt = lastVerifiedAt
    }
}
