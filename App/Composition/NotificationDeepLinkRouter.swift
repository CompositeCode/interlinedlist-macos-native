// NotificationDeepLinkRouter
//
// App-layer extension that closes the loop between
// `LocalNotificationScheduler` (which embeds a typed `userInfo` dict
// into every scheduled banner) and `AppDelegate` (which reads that dict
// back from a tapped `UNNotificationResponse` and reconstructs a
// `NotificationTarget`).
//
// The keys are namespaced under `"interlinedlist."` to avoid collisions
// with any APNs aps payload keys the server might include in a push
// notification's userInfo dict.
//
// Architecture notes
// ------------------
// * This file lives in `App/Composition/`, which is allowed to cross
//   every layer boundary per Decision 0003.
// * It extends `NotificationTarget` (a domain type) with an App-layer
//   initialiser that understands the `userInfo` key contract. The domain
//   package itself stays ignorant of userInfo dicts — that detail belongs
//   at the app boundary, not in the reusable domain layer.
// * `NotificationUserInfoKeys` is `enum` (no instantiation) to serve as
//   a namespace; all values are compile-time `static let` strings.

import Foundation
import InterlinedDomain

// MARK: - userInfo key constants

/// Stable string constants for the keys
/// `LocalNotificationScheduler` writes into
/// `UNMutableNotificationContent.userInfo` when scheduling a local
/// notification banner, and that `AppDelegate` reads back from a tapped
/// `UNNotificationResponse`.
enum NotificationUserInfoKeys {
    /// The domain `Notification.id` — used to identify which row to mark
    /// read after the user taps the banner.
    static let notificationId   = "interlinedlist.notificationId"
    /// The raw `NotificationKind` string (`"dig"`, `"reply"`, …). Used
    /// to reconstruct the kind so `NotificationTarget.init(userInfo:)`
    /// can follow the same dispatch table as `NotificationMappers.swift`.
    static let type             = "interlinedlist.type"
    /// Present when the target is `.message(id:)`.
    static let targetMessageId  = "interlinedlist.targetMessageId"
    /// Present when the target is `.list(id:)`.
    static let targetListId     = "interlinedlist.targetListId"
    /// Present when the target is `.user(id:)`.
    static let targetUserId     = "interlinedlist.targetUserId"
    /// Present when the target is `.organization(id:)`.
    static let targetOrgId      = "interlinedlist.targetOrgId"
    /// The actor's username — purely informational, not used for routing.
    static let actorUsername    = "interlinedlist.actorUsername"
    /// Fallback URL string for `.unknown(actionURL:)` targets.
    static let actionUrl        = "interlinedlist.actionUrl"
}

// MARK: - NotificationTarget + userInfo parsing

extension NotificationTarget {

    /// Reconstructs a typed `NotificationTarget` from the `userInfo` dict
    /// embedded by `LocalNotificationScheduler`. Returns
    /// `.unknown(actionURL:)` whenever the dict does not carry enough
    /// information to produce a more specific target — callers can still
    /// open a web fallback via the `actionURL` associated value in that
    /// case.
    ///
    /// Mirrors the dispatch table in `NotificationMappers.swift` so the
    /// two ends of the banner round-trip stay in sync: the mapper turns
    /// server DTO metadata into a target; this initialiser turns app
    /// userInfo back into the same target.
    init(userInfo: [AnyHashable: Any]) {
        let typeString  = userInfo[NotificationUserInfoKeys.type] as? String
        let kind        = NotificationKind(rawValue: typeString)
        let actionURL   = (userInfo[NotificationUserInfoKeys.actionUrl] as? String)
            .flatMap(URL.init(string:))

        switch kind {
        case .dig, .reply, .mention:
            if let id = userInfo[NotificationUserInfoKeys.targetMessageId] as? String {
                self = .message(id: id)
                return
            }

        case .listShared, .listRowAdded:
            if let id = userInfo[NotificationUserInfoKeys.targetListId] as? String {
                self = .list(id: id)
                return
            }

        case .followRequest, .followAccepted:
            if let id = userInfo[NotificationUserInfoKeys.targetUserId] as? String {
                self = .user(id: id)
                return
            }

        case .orgInvite:
            if let id = userInfo[NotificationUserInfoKeys.targetOrgId] as? String {
                self = .organization(id: id)
                return
            }

        case .other:
            break
        }

        self = .unknown(actionURL: actionURL)
    }
}
