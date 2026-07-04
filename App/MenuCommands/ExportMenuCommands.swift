// ExportMenuCommands
//
// Menu-bar commands for the M7 Data Export feature (PLAN.md §6 M7).
// Inserts an "Export…" submenu into the File group (after the New Item
// cluster) with one item per export type.
//
// Commands post `NSNotification`s that `MainWindowView` observes so the
// menu layer does not need to know about the view tree — the same
// cross-scene channel used by all other feature command files. Pure
// SwiftUI; no AppKit involvement.

import SwiftUI

// MARK: - Notification names

extension Notification.Name {
    /// Posted when the user invokes File > Export > My Posts.
    static let exportMessages = Notification.Name("InterlinedList.exportMessages")

    /// Posted when the user invokes File > Export > My Lists.
    static let exportLists = Notification.Name("InterlinedList.exportLists")

    /// Posted when the user invokes File > Export > List Data Rows.
    static let exportListDataRows = Notification.Name("InterlinedList.exportListDataRows")

    /// Posted when the user invokes File > Export > Follows.
    static let exportFollows = Notification.Name("InterlinedList.exportFollows")
}

// MARK: - ExportMenuCommands

struct ExportMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            ExportMenuButtons()
        }
    }
}

// MARK: - ExportMenuButtons

private struct ExportMenuButtons: View {
    var body: some View {
        Menu("Export…") {
            Button("My Posts…") {
                NotificationCenter.default.post(name: .exportMessages, object: nil)
            }
            Button("My Lists…") {
                NotificationCenter.default.post(name: .exportLists, object: nil)
            }
            Button("List Data Rows…") {
                NotificationCenter.default.post(name: .exportListDataRows, object: nil)
            }
            Button("Follows…") {
                NotificationCenter.default.post(name: .exportFollows, object: nil)
            }
        }
    }
}
