// DirectMessagesMenuCommands
//
// Menu-bar command for the Direct Messages feature (the-gaps.md G1). Adds
// a single "Messages" command that routes the sidebar to the Messages
// section:
//   - Messages  (⌥⌘M) — select the Messages sidebar row.
//
// Keybinding choice: ⌥⌘M is unused elsewhere (compose owns ⌘N / ⇧⌘N /
// ⌥⌘N, search owns ⌘F, notifications own ⌘0). ⌘M is reserved by macOS
// for Minimize, so we add the Option modifier.
//
// The command fans out via `NSNotification` — the same cross-scene channel
// the other menu commands use. `MainWindowView` observes
// `.directMessagesShow` to switch the sidebar. Pure SwiftUI.

import SwiftUI

struct DirectMessagesMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Direct Messages") {
                NotificationCenter.default.post(name: .directMessagesShow, object: nil)
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
        }
    }
}
