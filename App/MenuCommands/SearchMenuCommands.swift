// SearchMenuCommands
//
// Menu-bar command for the global search feature (the-gaps.md G5). Adds
// a single `Find` command under a dedicated menu:
//   - Search…  (⌘F) — route the sidebar to the Search section and focus
//                      the search field.
//
// Keybinding choice:
//   - ⌘F is the platform-standard "Find" accelerator. It is unused
//     elsewhere in the app (compose owns ⌘N / ⇧⌘N / ⌥⌘N, notifications
//     own ⌘0, documents / lists own their own set), so ⌘F is free.
//
// The command fans out via `NSNotification` — the same cross-scene
// channel the other menu commands use. `MainWindowView` observes
// `.searchShow` to switch the sidebar; `SearchRootView` observes
// `.searchFocus` to focus the field. Pure SwiftUI; no AppKit involvement.

import SwiftUI

extension Foundation.Notification.Name {
    /// Posted when the user invokes Find → Search…. `MainWindowView`
    /// observes this and selects the `.search` sidebar row, then re-posts
    /// `.searchFocus` so the field takes focus once the view is on screen.
    static let searchShow = Foundation.Notification.Name("InterlinedList.searchShow")

    /// Posted after the sidebar has switched to `.search`. `SearchRootView`
    /// observes this and focuses its text field.
    static let searchFocus = Foundation.Notification.Name("InterlinedList.searchFocus")

    /// Posted when the user taps a document hit in the search results.
    /// `MainWindowView` observes this and selects the `.documents`
    /// sidebar row (there is no typed `.documents` deep-link target).
    static let searchShowDocuments = Foundation.Notification.Name("InterlinedList.searchShowDocuments")
}

struct SearchMenuCommands: Commands {
    var body: some Commands {
        // Place the Find command in the standard text-editing menu area by
        // using `.textEditing`; a dedicated `CommandMenu` keeps it discoverable
        // even when no text field owns first responder.
        CommandMenu("Find") {
            SearchMenuButtons()
        }
    }
}

private struct SearchMenuButtons: View {
    var body: some View {
        Button("Search\u{2026}") {
            NotificationCenter.default.post(name: .searchShow, object: nil)
        }
        .keyboardShortcut("f", modifiers: [.command])
    }
}
