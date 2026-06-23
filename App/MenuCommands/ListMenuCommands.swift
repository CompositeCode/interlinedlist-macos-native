// ListMenuCommands
//
// Menu-bar commands for the M3 Lists feature (PLAN.md §6 M3).
// Adds a `Lists` menu with a "New List" command bound to ⇧⌘N so
// it does not collide with the composer's ⌘N (`ComposeCommands`).
//
// The command posts an `NSNotification` (`.openNewListSheet`) so
// the `OwnedListsRootView` can present its sheet. This is the
// simplest cross-scene channel available in pure SwiftUI without
// reaching into AppKit.

import SwiftUI

extension Notification.Name {
    /// Posted when the user invokes File / Lists → New List.
    /// `OwnedListsRootView` observes this and presents the sheet.
    static let openNewListSheet = Notification.Name("InterlinedList.openNewListSheet")
}

struct ListMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Lists") {
            ListsMenuButtons()
        }
    }
}

private struct ListsMenuButtons: View {
    var body: some View {
        Button("New List") {
            NotificationCenter.default.post(name: .openNewListSheet, object: nil)
        }
        .keyboardShortcut("n", modifiers: [.shift, .command])
    }
}
