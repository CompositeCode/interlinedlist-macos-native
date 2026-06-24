import Foundation
import InterlinedDomain

/// Internal mapping between SwiftData `NotificationRecord` and the domain
/// `Notification` value type. Mirrors the `MessageRecordMapping` pattern from
/// Wave 2 — `@Model` instances stay inside the actor, only `Sendable` value
/// types cross the boundary (critical under Swift 6 strict concurrency).
///
/// Foundation also declares a `Notification` type, which shadows the
/// domain's `Notification` under plain `import Foundation`. The module-
/// qualified form `InterlinedDomain.Notification` resolves unambiguously
/// to the domain value (the namespace marker enum is named
/// `InterlinedDomain_Module` for exactly this reason — see
/// `InterlinedDomain/InterlinedDomain.swift`).

/// Tag strings stored in `NotificationRecord.targetKind` discriminating the
/// `NotificationTarget` enum case. The strings are deliberately stable —
/// changing one is a migration.
enum NotificationTargetTag {
    static let message = "message"
    static let list = "list"
    static let user = "user"
    static let organization = "organization"
    static let unknown = "unknown"
}

extension NotificationRecord {

    /// Build a new record from a domain `Notification`.
    convenience init(from notification: InterlinedDomain.Notification) {
        let target = notification.target
        let (kindTag, idValue, urlValue) = NotificationRecord.encode(target: target)
        self.init(
            id: notification.id,
            kindRaw: notification.kind.rawValue,
            actorID: notification.actor?.id,
            actorUsername: notification.actor?.username,
            actorDisplayName: notification.actor?.displayName,
            actorAvatarURLString: notification.actor?.avatarURL?.absoluteString,
            targetKind: kindTag,
            targetID: idValue,
            actionURLString: urlValue,
            createdAt: notification.createdAt,
            isRead: notification.isRead,
            readAt: notification.readAt,
            title: notification.title,
            body: notification.body
        )
    }

    /// Copy fresh field values from a domain `Notification` into an existing
    /// managed record — the upsert path. Every mutable field gets touched so
    /// stale state cannot leak through.
    func apply(_ notification: InterlinedDomain.Notification) {
        // `id` is the primary key.
        kindRaw = notification.kind.rawValue
        actorID = notification.actor?.id
        actorUsername = notification.actor?.username
        actorDisplayName = notification.actor?.displayName
        actorAvatarURLString = notification.actor?.avatarURL?.absoluteString
        let (kindTag, idValue, urlValue) = NotificationRecord.encode(target: notification.target)
        targetKind = kindTag
        targetID = idValue
        actionURLString = urlValue
        createdAt = notification.createdAt
        isRead = notification.isRead
        readAt = notification.readAt
        title = notification.title
        body = notification.body
    }

    /// Hydrate the row into a domain `Notification` value.
    func toNotification() -> InterlinedDomain.Notification {
        let actor: UserSummary? = actorID.map { id in
            UserSummary(
                id: id,
                username: actorUsername ?? id,
                displayName: actorDisplayName ?? actorUsername ?? id,
                avatarURL: actorAvatarURLString.flatMap(URL.init(string:))
            )
        }
        return InterlinedDomain.Notification(
            id: id,
            kind: NotificationKind(rawValue: kindRaw),
            actor: actor,
            target: decodeTarget(),
            createdAt: createdAt,
            isRead: isRead,
            readAt: readAt,
            title: title,
            body: body
        )
    }

    /// Encodes a domain target into the flat-fields shape the record stores.
    /// Returns the discriminator tag, the typed-target id (when applicable),
    /// and the raw action URL string (only set for `.unknown`).
    private static func encode(target: NotificationTarget?) -> (kindTag: String?, id: String?, url: String?) {
        guard let target else { return (nil, nil, nil) }
        switch target {
        case .message(let id):
            return (NotificationTargetTag.message, id, nil)
        case .list(let id):
            return (NotificationTargetTag.list, id, nil)
        case .user(let id):
            return (NotificationTargetTag.user, id, nil)
        case .organization(let id):
            return (NotificationTargetTag.organization, id, nil)
        case .unknown(let url):
            return (NotificationTargetTag.unknown, nil, url?.absoluteString)
        }
    }

    /// Inverse of `encode(target:)`.
    private func decodeTarget() -> NotificationTarget? {
        guard let kind = targetKind else { return nil }
        switch kind {
        case NotificationTargetTag.message:
            return targetID.map { .message(id: $0) }
        case NotificationTargetTag.list:
            return targetID.map { .list(id: $0) }
        case NotificationTargetTag.user:
            return targetID.map { .user(id: $0) }
        case NotificationTargetTag.organization:
            return targetID.map { .organization(id: $0) }
        case NotificationTargetTag.unknown:
            return .unknown(actionURL: actionURLString.flatMap(URL.init(string:)))
        default:
            // Unknown tag value (a future migration may add one). Treat as
            // `.unknown(nil)` so the row still hydrates.
            return .unknown(actionURL: actionURLString.flatMap(URL.init(string:)))
        }
    }
}
