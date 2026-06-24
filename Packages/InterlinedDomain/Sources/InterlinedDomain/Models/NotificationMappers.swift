import Foundation
import InterlinedKit

// MARK: - Notification DTO → domain mapping
//
// Per-group slice of the audit-in-one-place mapper convention (PLAN.md §3).
// The Notifications surface ships in M5 (PLAN.md §6 M5); per decision 0003
// the App layer never references the kit DTOs — `NotificationsService`
// returns `NotificationTray` and `Notification` values, and this file is the
// one place that crosses the boundary.

extension Notification {

    /// Maps a `NotificationDTO` (wire shape) to the domain value. Tolerant of
    /// missing fields: the wire contract makes nearly everything optional;
    /// only `id` is guaranteed.
    public init(from dto: NotificationDTO) {
        let kind = NotificationKind(rawValue: dto.type)
        let actor = Self.actor(from: dto.metadata)
        let target = NotificationTarget(from: dto, kind: kind)
        self.init(
            id: dto.id,
            kind: kind,
            actor: actor,
            target: target,
            createdAt: dto.createdAt,
            isRead: dto.readAt != nil,
            readAt: dto.readAt,
            title: dto.title,
            body: dto.body
        )
    }

    /// Reads the `actor` (the user who initiated the notification) out of
    /// the metadata map. The wire shape varies by kind — `dig` and `reply`
    /// have `actorId` / `actorUsername` / `actorAvatar`; `follow_request`
    /// embeds the same trio. When neither shape is present `nil` is
    /// returned and the App layer renders a system-origin row.
    fileprivate static func actor(
        from metadata: [String: NotificationMetadataValue]?
    ) -> UserSummary? {
        guard
            let metadata,
            let actorId = metadata["actorId"]?.stringValue
        else { return nil }
        let username = metadata["actorUsername"]?.stringValue ?? actorId
        let displayName = metadata["actorDisplayName"]?.stringValue ?? username
        let avatarString = metadata["actorAvatar"]?.stringValue
        return UserSummary(
            id: actorId,
            username: username,
            displayName: displayName,
            avatarURL: avatarString.flatMap(URL.init(string:))
        )
    }
}

extension NotificationTray {

    /// Maps the tray envelope to the domain value. Every item passes through
    /// the per-row mapper above.
    public init(from dto: NotificationTrayDTO) {
        self.init(
            unreadCount: dto.unreadCount,
            items: dto.items.map(Notification.init(from:))
        )
    }
}

extension NotificationTarget {

    /// Routes the raw notification to a typed target by inspecting `kind`
    /// and the metadata payload. Falls back to `.unknown(actionURL:)` when
    /// the metadata does not carry the keys the kind expects — that keeps
    /// the projection total (the App layer always has a switchable value)
    /// while preserving the raw `actionUrl` for a generic deep link.
    public init(from dto: NotificationDTO, kind: NotificationKind) {
        let metadata = dto.metadata
        let actionURL = dto.actionUrl.flatMap(URL.init(string:))

        switch kind {
        case .dig, .reply, .mention:
            if let messageId = metadata?["messageId"]?.stringValue {
                self = .message(id: messageId)
                return
            }

        case .listShared, .listRowAdded:
            if let listId = metadata?["listId"]?.stringValue {
                self = .list(id: listId)
                return
            }

        case .followRequest, .followAccepted:
            // The `actorId` key on these rows is the user the row is
            // *about* (the requester / approver), which is also the deep-
            // link target — opening the profile of the person who acted.
            if let userId = metadata?["actorId"]?.stringValue
                ?? metadata?["userId"]?.stringValue {
                self = .user(id: userId)
                return
            }

        case .orgInvite:
            if let orgId = metadata?["organizationId"]?.stringValue
                ?? metadata?["orgId"]?.stringValue {
                self = .organization(id: orgId)
                return
            }

        case .other:
            break
        }

        self = .unknown(actionURL: actionURL)
    }
}

// MARK: - NotificationMetadataValue helpers

extension NotificationMetadataValue {
    /// Pulls a `String` out of the metadata map's flexible value. Most keys
    /// the M5 mappers care about (`messageId`, `listId`, …) arrive as
    /// strings; this helper keeps the call sites compact.
    fileprivate var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
