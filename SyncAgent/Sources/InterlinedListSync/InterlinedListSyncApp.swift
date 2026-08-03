import SwiftUI
import InterlinedListSyncCore

/// Entry point for the InterlinedList Sync menu-bar agent. All behavior lives in
/// ``AppDelegate`` (in the Core module); this app has no windows of its own —
/// preferences open on demand and the UI is the menu-bar status item.
@main
struct InterlinedListSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Required to satisfy the App protocol; the agent presents no scene of
        // its own. An empty Settings scene keeps the process alive as an agent.
        Settings { EmptyView() }
    }
}
