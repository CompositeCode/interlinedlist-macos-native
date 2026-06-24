// NotificationsMenuCommands
//
// Menu-bar commands for the M5 Notifications feature (PLAN.md §6 M5).
// Adds a `Notifications` menu with:
//   - Show Notifications  (⌘0)         — focus the sidebar's
//                                          Notifications row.
//   - Mark All as Read    (⌥⌘R)        — fans out via
//                                          `.notificationsMarkAllRead`.
//   - Refresh             (⌃⌘R)        — fans out via
//                                          `.notificationsRefresh`.
//
// Keybinding choices:
//   - ⌘0 picks an unused numeric: ⌘1–⌘7 are reserved per PLAN.md §5
//     for sidebar sections via `Go` (planned), and the Lists / Documents
//     / Compose commands already claim ⇧⌘N / ⌥⌘N / ⌘N. ⌘0 fits
//     "the zeroth thing — notifications".
//   - ⌥⌘R for "Mark all as read" parallels Documents' ⌥⌘S "Sync Now"
//     — both option-modified action shortcuts.
//   - ⌃⌘R for "Refresh" avoids colliding with ⌘R, which several
//     macOS apps wire to a different in-app concept (e.g. "Run").
//
// Commands fan out via `NSNotification` to whatever view is rendering
// the tray — the same cross-scene channel `ListMenuCommands` and
// `DocumentsMenuCommands` use. Pure SwiftUI; no AppKit involvement.

import SwiftUI

extension Foundation.Notification.Name {
    /// Posted when the user invokes Notifications → Show Notifications.
    /// `MainWindowView` observes this and selects the `.notifications`
    /// sidebar row.
    static let notificationsShow = Foundation.Notification.Name("InterlinedList.notificationsShow")

    /// Posted when the user invokes Notifications → Mark All as Read.
    /// `NotificationsRootView` observes this and calls
    /// `NotificationsListViewModel.markAllRead()`.
    static let notificationsMarkAllRead = Foundation.Notification.Name("InterlinedList.notificationsMarkAllRead")

    /// Posted when the user invokes Notifications → Refresh. The tray
    /// view triggers a re-fetch.
    static let notificationsRefresh = Foundation.Notification.Name("InterlinedList.notificationsRefresh")
}

struct NotificationsMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Notifications") {
            NotificationsMenuButtons()
        }
    }
}

private struct NotificationsMenuButtons: View {
    var body: some View {
        Button("Show Notifications") {
            NotificationCenter.default.post(name: .notificationsShow, object: nil)
        }
        .keyboardShortcut("0", modifiers: [.command])

        Divider()

        Button("Mark All as Read") {
            NotificationCenter.default.post(name: .notificationsMarkAllRead, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.option, .command])

        Button("Refresh") {
            NotificationCenter.default.post(name: .notificationsRefresh, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.control, .command])
    }
}
