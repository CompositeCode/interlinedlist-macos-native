// ComposeCommands
//
// Menu-bar commands that open the composer window (PLAN.md §5 — "⌘N
// anywhere"). Replaces the default "New" command in the File menu so
// the shortcut maps to "New Post" rather than SwiftUI's no-op default.
//
// The command is intentionally minimal: it just calls `openWindow(id:)`
// to bring up a fresh composer scene. All compose state lives inside
// the window's own `ComposerViewModel`.

import SwiftUI

/// Stable identifier for the composer window scene. Used by both the
/// menu command and the `Window` scene declaration in
/// `InterlinedListApp` so the two stay in lock-step.
enum ComposeWindowID {
    static let newPost = "compose-new-post"
}

struct ComposeCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            ComposeMenuButton()
        }
    }
}

/// Extracted into its own view so we can read `@Environment(\.openWindow)`
/// — `Commands` types cannot use `@Environment` directly because they
/// are not rendered in a view tree.
private struct ComposeMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Post") {
            openWindow(id: ComposeWindowID.newPost)
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}
