// SocialMenuCommands
//
// Menu-bar commands for the M5 Social Roster panel (PLAN.md §1
// "Follow system", §6 M5). Adds a `Connections` menu with:
//   - Show Followers   (⌃⌘1) — opens the panel on the Followers tab.
//   - Show Following   (⌃⌘2) — opens the panel on the Following tab.
//   - Show Requests    (⌃⌘3) — opens the panel on the Requests tab.
//
// The notifications-tray and dedicated Requests-panel both surface
// pending follow requests; the deep-link from this menu always lands
// in the dedicated panel since the menu is the user's "go to the
// management surface" intent.
//
// Pure SwiftUI fan-out via `NSNotification` — same pattern as the
// Lists / Documents / Notifications menu commands.

import SwiftUI

extension Foundation.Notification.Name {
    /// Posted when the user invokes Connections → Show Followers.
    static let socialShowFollowers = Foundation.Notification.Name("InterlinedList.socialShowFollowers")
    /// Posted when the user invokes Connections → Show Following.
    static let socialShowFollowing = Foundation.Notification.Name("InterlinedList.socialShowFollowing")
    /// Posted when the user invokes Connections → Show Requests.
    static let socialShowRequests = Foundation.Notification.Name("InterlinedList.socialShowRequests")
}

struct SocialMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Connections") {
            SocialMenuButtons()
        }
    }
}

private struct SocialMenuButtons: View {
    var body: some View {
        Button("Show Followers") {
            NotificationCenter.default.post(name: .socialShowFollowers, object: nil)
        }
        .keyboardShortcut("1", modifiers: [.control, .command])

        Button("Show Following") {
            NotificationCenter.default.post(name: .socialShowFollowing, object: nil)
        }
        .keyboardShortcut("2", modifiers: [.control, .command])

        Button("Show Requests") {
            NotificationCenter.default.post(name: .socialShowRequests, object: nil)
        }
        .keyboardShortcut("3", modifiers: [.control, .command])
    }
}
