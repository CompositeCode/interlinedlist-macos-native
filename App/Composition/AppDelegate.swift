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

/// `NSApplicationDelegate` adapter installed via
/// `@NSApplicationDelegateAdaptor` in `InterlinedListApp`. Owns:
///
/// 1. The dock-tile badge writer (`updateDockBadge(unreadCount:)`).
/// 2. The `UNUserNotificationCenterDelegate` hook so that activating a
///    delivered notification brings the app forward (deep-link routing
///    proper lands in a follow-up — see `// TODO(M5.x)` below).
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

    /// Called when the user clicks a delivered notification. Routes the
    /// main window to the Notifications sidebar section and activates
    /// the app. The `NotificationsRootView` will refresh on appear so
    /// the relevant item is visible.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .notificationsShow, object: nil)
        completionHandler()
    }
}
