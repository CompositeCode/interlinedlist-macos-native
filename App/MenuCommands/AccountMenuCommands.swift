// AccountMenuCommands
//
// Adds the "Sign Out" item to the app menu (after "Settings…").
// Per the project's notification-based menu-command pattern, this
// file posts a `Notification.Name` that the session-aware root view
// (`AppRootView`) picks up and converts into an async `signOut()` call.
// This keeps the Commands struct dependency-free — it never needs to
// import the session or the app environment.

import SwiftUI

extension Notification.Name {
    static let accountSignOut = Notification.Name("InterlinedList.accountSignOut")
}

struct AccountMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Divider()
            Button("Sign Out") {
                NotificationCenter.default.post(name: .accountSignOut, object: nil)
            }
        }
    }
}
