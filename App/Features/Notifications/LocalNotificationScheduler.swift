// LocalNotificationScheduler
//
// Schedules a macOS `UNUserNotification` banner for a single
// `InterlinedDomain.Notification` value. The scheduler embeds a typed
// `userInfo` dict — keyed by `NotificationUserInfoKeys` — so that
// `AppDelegate` can reconstruct a `NotificationTarget` when the user
// taps the delivered banner (the deep-link routing half of the
// notification feature, per PLAN.md §6 M5.x).
//
// Responsibilities
// ----------------
// * Build a `UNMutableNotificationContent` with title, sound, and userInfo.
// * Schedule an immediate `UNNotificationRequest` via the shared
//   `UNUserNotificationCenter`.
// * NOT request UN permission — that belongs to
//   `NotificationsPermissionCoordinator`.
// * NOT de-duplicate previously-shown notifications — callers own that
//   set. The composition root can track shown IDs in `UserDefaults`.
//
// Per Decision 0003 this file imports only `InterlinedDomain`; it does
// not import `InterlinedKit`. The `NotificationUserInfoKeys` constants
// are in `App/Composition/` and are visible to all files in the
// `InterlinedList` module without an extra import.

import Foundation
import UserNotifications
import InterlinedDomain

// MARK: - Protocol

/// Narrow scheduling surface for App-layer code that needs to surface
/// an `InterlinedDomain.Notification` as a macOS system banner. A
/// protocol so unit tests can inject a recording stub without touching
/// `UNUserNotificationCenter`.
protocol LocalNotificationScheduling: Sendable {
    /// Schedules a local notification banner for `notification`.
    /// Idempotent by request identifier (`notification.id`) — scheduling
    /// the same id twice replaces the earlier pending request.
    func schedule(_ notification: InterlinedDomain.Notification) async
}

// MARK: - Live implementation

/// Production scheduler. Delegates to `UNUserNotificationCenter`; the
/// center is injected so test overrides work without the real system.
final class LocalNotificationScheduler: LocalNotificationScheduling, @unchecked Sendable {

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func schedule(_ notification: InterlinedDomain.Notification) async {
        let content = UNMutableNotificationContent()
        content.title = derivedTitle(for: notification)
        if let body = notification.body, !body.isEmpty {
            content.body = body
        }
        content.sound = .default
        content.userInfo = Self.userInfo(for: notification)

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil // nil trigger = deliver immediately
        )
        // Swallow scheduling errors: if the user has denied permission the
        // banner silently drops; the in-app tray still shows the row.
        try? await center.add(request)
    }

    // MARK: - userInfo builder

    /// Assembles the `userInfo` dict that `AppDelegate` reads back from
    /// `UNNotificationResponse.notification.request.content.userInfo`
    /// when the user taps the delivered banner.
    ///
    /// All keys use the `NotificationUserInfoKeys` constants so the
    /// writing and reading sides of the contract share a single source of
    /// truth and are immune to typos.
    static func userInfo(
        for notification: InterlinedDomain.Notification
    ) -> [String: String] {
        var dict: [String: String] = [:]
        dict[NotificationUserInfoKeys.notificationId]  = notification.id
        dict[NotificationUserInfoKeys.type]            = notification.kind.rawValue

        if let username = notification.actor?.username, !username.isEmpty {
            dict[NotificationUserInfoKeys.actorUsername] = username
        }

        switch notification.target {
        case .message(let id):
            dict[NotificationUserInfoKeys.targetMessageId] = id
        case .list(let id):
            dict[NotificationUserInfoKeys.targetListId]    = id
        case .user(let id):
            dict[NotificationUserInfoKeys.targetUserId]    = id
        case .organization(let id):
            dict[NotificationUserInfoKeys.targetOrgId]     = id
        case .unknown(let url):
            if let urlString = url?.absoluteString {
                dict[NotificationUserInfoKeys.actionUrl] = urlString
            }
        case .none:
            break
        }

        return dict
    }

    // MARK: - Title derivation

    /// Falls back to `NotificationRowCopy.copy` when the server-supplied
    /// title is absent so every banner has human-readable text.
    private func derivedTitle(for note: InterlinedDomain.Notification) -> String {
        NotificationRowCopy.copy(
            for: note.kind,
            actor: note.actor,
            title: note.title,
            body: nil
        )
    }
}
