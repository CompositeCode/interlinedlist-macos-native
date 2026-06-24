import Foundation

/// A single notification as the M5 tray and the native `UNUserNotification`
/// delivery code render it (PLAN.md §1 "Notifications", §6 M5).
///
/// Domain projection of `InterlinedKit.NotificationDTO`. The DTO carries a
/// free-form `metadata` map and a stringly-typed `type`; the domain shape
/// distills both into typed `kind` + `target` values so the App layer never
/// reads the raw map. The author identity (`actor`) is optional because
/// system-originated notifications (e.g. the `list_row_added` rows added by
/// a GitHub refresh job) have no actor user.
///
/// **Why a distinct `Notification` type rather than reusing `Message`-style
/// fields.** Notifications are a separate domain — they reference messages /
/// lists / users by id but are not themselves any of those things. Modelling
/// them as their own value keeps the M5 tray UI free of accidental coupling
/// to `Message` and lets the SwiftData mirror row stay flat.
public struct Notification: Sendable, Equatable, Hashable, Identifiable {

    public let id: String

    /// The typed kind — see `NotificationKind` for the closed set and the
    /// `.other(String)` forward-compat case.
    public let kind: NotificationKind

    /// The user who initiated the notification (the dig-er, the replier,
    /// the requester). `nil` for system-originated rows.
    public let actor: UserSummary?

    /// The deep-link target the row routes to on activation. `.unknown` when
    /// the metadata map did not yield a typed projection — see
    /// `NotificationTarget`.
    public let target: NotificationTarget?

    /// When the notification was created on the server. `nil` only when the
    /// server omits it (defensive — every live response we have seen carries
    /// it).
    public let createdAt: Date?

    /// True when the notification has been read. The wire shape carries this
    /// as a `readAt: Date?`; the domain layer collapses to a flag for the
    /// tray UI and exposes the timestamp separately when callers need it.
    public let isRead: Bool

    /// The raw `readAt` timestamp from the wire, preserved for callers that
    /// need to order or display when a row was read. `nil` when unread.
    public let readAt: Date?

    /// A short, server-supplied title. Used for the row's primary line in
    /// the tray and the native banner. `nil` when the server didn't send
    /// one — the App layer derives a fallback from `kind` and `actor` in
    /// that case.
    public let title: String?

    /// A short, server-supplied body. Optional for the same reason as
    /// `title`.
    public let body: String?

    public init(
        id: String,
        kind: NotificationKind,
        actor: UserSummary?,
        target: NotificationTarget?,
        createdAt: Date?,
        isRead: Bool,
        readAt: Date? = nil,
        title: String? = nil,
        body: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.actor = actor
        self.target = target
        self.createdAt = createdAt
        self.isRead = isRead
        self.readAt = readAt
        self.title = title
        self.body = body
    }
}

// MARK: - NotificationTray

/// The full M5 tray envelope (PLAN.md §1 "Notifications", §6 M5).
///
/// Domain projection of `InterlinedKit.NotificationTrayDTO`. `unreadCount` is
/// the server-side authoritative count, used to render the sidebar badge
/// (which can be larger than `items.count` if the user has read some rows
/// elsewhere or the server tray cap clipped the items list).
public struct NotificationTray: Sendable, Equatable {

    /// The number of unread notifications, server-authoritative. Distinct
    /// from `items.filter { !$0.isRead }.count` because the items list is
    /// capped server-side by `notificationTrayLimit` (10–40, default 20).
    public let unreadCount: Int

    /// The page of notifications the server returned. Newest-first.
    public let items: [Notification]

    public init(unreadCount: Int, items: [Notification]) {
        self.unreadCount = unreadCount
        self.items = items
    }

    /// An empty tray — boundary value for tests and first-load shimmer.
    public static let empty = NotificationTray(unreadCount: 0, items: [])
}
