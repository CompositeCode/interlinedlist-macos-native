// DocumentsMenuCommands
//
// Menu-bar commands for the M4 Documents feature (PLAN.md §6 M4).
// Adds a `Documents` menu with:
//   - New Document (⌥⌘N) — opt-modifier to avoid colliding with the
//     composer's ⌘N (`ComposeCommands`) and the Lists ⇧⌘N
//     (`ListMenuCommands`).
//   - Sync Now (⌥⌘S) — manual sync trigger; the on-launch auto-sync
//     lives in `InterlinedListApp.swift`.
//
// Commands post `NSNotification`s the `DocumentsRootView` listens for —
// the same cross-scene channel `ListMenuCommands` uses. Pure SwiftUI;
// no AppKit involvement.

import SwiftUI

extension Notification.Name {
    /// Posted when the user invokes Documents → New Document.
    /// `DocumentsRootView` observes this and creates a new document
    /// in the currently-selected folder.
    static let documentsNewDocument = Notification.Name("InterlinedList.documentsNewDocument")

    /// Posted when the user invokes Documents → Sync Now. The same
    /// notification fires from the toolbar button so the sync path is
    /// single-sourced.
    static let documentsSyncNow = Notification.Name("InterlinedList.documentsSyncNow")
}

struct DocumentsMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Documents") {
            DocumentsMenuButtons()
        }
    }
}

private struct DocumentsMenuButtons: View {
    var body: some View {
        Button("New Document") {
            NotificationCenter.default.post(name: .documentsNewDocument, object: nil)
        }
        .keyboardShortcut("n", modifiers: [.option, .command])

        Button("Sync Now") {
            NotificationCenter.default.post(name: .documentsSyncNow, object: nil)
        }
        .keyboardShortcut("s", modifiers: [.option, .command])
    }
}
