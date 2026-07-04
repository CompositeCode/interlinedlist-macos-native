// UpdatesMenuCommands
//
// Adds "Check for Updates..." to the application menu (the app-named
// menu at the left of the menu bar), inserted immediately after the
// "About InterlinedList" item. This placement follows macOS convention
// (HIG: "Put the Check for Updates item in the app menu").
//
// The command delegates directly to SparkleController, which is held by
// InterlinedListApp for the app's lifetime. Sparkle opens its own update
// UI; no SwiftUI view-tree involvement is needed.

import SwiftUI

/// Commands that surface the Sparkle "Check for Updates..." action.
///
/// Placed after `.appInfo` so the item appears immediately after
/// "About InterlinedList" in the application menu — the standard macOS
/// position for update-check commands.
struct UpdatesMenuCommands: Commands {

    /// The Sparkle controller owned at the composition root. Captured
    /// once at scene construction and valid for the app's lifetime.
    let sparkleController: SparkleController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                sparkleController.checkForUpdates()
            }
        }
    }
}
