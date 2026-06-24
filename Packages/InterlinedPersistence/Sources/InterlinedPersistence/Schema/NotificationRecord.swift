import Foundation
import SwiftData

/// SwiftData record for a cached `Notification` (PLAN.md §1 "Notifications",
/// §5 stale-while-revalidate, §6 M5 tray cache).
///
/// Mirrors the round-trip surface of `InterlinedDomain.Notification`. The
/// notification kind is stored as the wire-string (`NotificationKind.rawValue`)
/// so adding a new typed case is a domain-only change — the on-disk schema
/// does not migrate when a `.other("foo")` value gets promoted to a typed
/// case.
///
/// The deep-link `NotificationTarget` is stored as two fields (`targetKind`
/// + `targetID`) plus the raw `actionURLString` so the `.unknown(actionURL:)`
/// case round-trips losslessly. Trying to serialise the enum directly into
/// SwiftData would require either a custom transformer or a JSON blob — both
/// add cost for no semantic gain over the flat-fields shape.
///
/// The denormalised actor identity matches the `MessageRecord` author
/// pattern from Wave 2: the tray can render on first paint without a join.
///
/// Internal to the package: `SwiftDataNotificationStore` consumers only see
/// `Notification` values across the actor boundary.
@Model
final class NotificationRecord {

    @Attribute(.unique) var id: String

    /// Wire string for the kind (`"dig"`, `"reply"`, …, or any future
    /// server-emitted value). Domain mapping reuses
    /// `NotificationKind(rawValue:)`.
    var kindRaw: String

    /// Denormalised actor identity. All three fields are nil for
    /// system-originated rows.
    var actorID: String?
    var actorUsername: String?
    var actorDisplayName: String?
    var actorAvatarURLString: String?

    /// Target discriminator — `"message"`, `"list"`, `"user"`,
    /// `"organization"`, or `"unknown"`. `nil` only when the row had no
    /// target at all (an unusual case the protocol allows).
    var targetKind: String?
    /// Target id when the target is `.message` / `.list` / `.user` /
    /// `.organization`.
    var targetID: String?
    /// Raw action URL string for the `.unknown(actionURL:)` case (preserved
    /// so the generic "open in browser" fallback works). `nil` when the
    /// target is a typed one or the wire shape had no `actionUrl`.
    var actionURLString: String?

    var createdAt: Date?
    var isRead: Bool
    var readAt: Date?

    var title: String?
    var body: String?

    init(
        id: String,
        kindRaw: String,
        actorID: String?,
        actorUsername: String?,
        actorDisplayName: String?,
        actorAvatarURLString: String?,
        targetKind: String?,
        targetID: String?,
        actionURLString: String?,
        createdAt: Date?,
        isRead: Bool,
        readAt: Date?,
        title: String?,
        body: String?
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.actorID = actorID
        self.actorUsername = actorUsername
        self.actorDisplayName = actorDisplayName
        self.actorAvatarURLString = actorAvatarURLString
        self.targetKind = targetKind
        self.targetID = targetID
        self.actionURLString = actionURLString
        self.createdAt = createdAt
        self.isRead = isRead
        self.readAt = readAt
        self.title = title
        self.body = body
    }
}

// MARK: - NotificationTrayRecord

/// Singleton-style row tracking the cached tray's metadata (PLAN.md §6 M5).
/// Mirrors the `SyncStateRecord` pattern from Wave 5: one row, keyed by a
/// constant `pageKey`, that holds the cross-row aggregates (`unreadCount`)
/// plus the cached row id order so re-reading the tray returns items in
/// the same newest-first order the server returned them in.
@Model
final class NotificationTrayRecord {

    /// Stable singleton key — always `"tray"`.
    @Attribute(.unique) var pageKey: String

    /// Server-authoritative unread count.
    var unreadCount: Int

    /// Ordered ids of the cached tray (newest first). The actual rows live
    /// in `NotificationRecord`; this list is the page-index that
    /// preserves order on read.
    var notificationIDs: [String]

    /// When the cached tray was last refreshed from the server. Surfaced to
    /// the UI as "Last updated 2m ago".
    var lastFetchedAt: Date?

    init(
        pageKey: String = "tray",
        unreadCount: Int = 0,
        notificationIDs: [String] = [],
        lastFetchedAt: Date? = nil
    ) {
        self.pageKey = pageKey
        self.unreadCount = unreadCount
        self.notificationIDs = notificationIDs
        self.lastFetchedAt = lastFetchedAt
    }
}
