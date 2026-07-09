// AppDelegate
//
// Narrow AppKit interop file per Decision 0005 — the sole purpose of
// this file is to write the macOS dock-tile badge for unread
// notifications, an API SwiftUI does not yet expose on macOS 15
// (PLAN.md §5 — "dock badge for unread"). The grep gate amended in
// Decision 0005 allows exactly this filename to `import AppKit`;
// any other App-target file that imports AppKit is a violation.
//
// Do NOT add other AppKit reaches here. The file's existence is a
// documented exception, not an invitation. If a future feature needs
// another AppKit API (`NSSavePanel`, `NSPasteboard`, `NSWorkspace`, …)
// pause and ask before extending this file — see `feedback_swiftui_only.md`.

import AppKit
import SwiftUI
import UserNotifications
import InterlinedDomain

/// `NSApplicationDelegate` adapter installed via
/// `@NSApplicationDelegateAdaptor` in `InterlinedListApp`. Owns:
///
/// 1. The dock-tile badge writer (`updateDockBadge(unreadCount:)`).
/// 2. The `UNUserNotificationCenterDelegate` hook that activates the app
///    and routes to the relevant content when the user taps a delivered
///    banner — see `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
///
/// Everything else stays pure SwiftUI.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Writes the dock-tile badge. Apple convention is to set the label
    /// to an empty string to hide the badge entirely when zero, rather
    /// than to render a literal `"0"` pip on the dock icon.
    @MainActor
    func updateDockBadge(unreadCount: Int) {
        let label = unreadCount > 0 ? String(unreadCount) : ""
        NSApp.dockTile.badgeLabel = label
    }

    // MARK: - Notification activation routing

    /// Installed by `NotificationsPermissionCoordinator` once the user
    /// grants UN permission. Receives the activated notification's
    /// response so a future deep-link router can route by
    /// `NotificationTarget`. For v1 the delegate simply brings the app
    /// to the front; the routing logic is a follow-up.
    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Show the banner while the app is in the foreground (otherwise
    /// the system suppresses it). The dock badge keeps the unread count.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Called when the user taps a delivered notification banner. Brings
    /// the app forward, then resolves a typed `NotificationTarget` from
    /// the banner's `userInfo` dict and posts `.notificationDeepLink` so
    /// `MainWindowView` can route the sidebar and feature views can push
    /// the relevant detail on their own navigation stacks.
    ///
    /// Fallback: when the `userInfo` dict does not carry enough keys to
    /// produce a typed target — e.g. any notification scheduled before
    /// this routing was added — the resolved target is
    /// `.unknown(actionURL: nil)` and `MainWindowView` falls back to
    /// selecting the Notifications sidebar section, preserving the
    /// pre-M5.x behaviour.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let userInfo = response.notification.request.content.userInfo
        let target = NotificationTarget(userInfo: userInfo)
        NotificationCenter.default.post(name: .notificationDeepLink, object: target)
        completionHandler()
    }
}
