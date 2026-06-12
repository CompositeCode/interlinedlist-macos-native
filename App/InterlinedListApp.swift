// InterlinedListApp
//
// App entry point. The full scene graph (compose window, document windows,
// onboarding) is wired up in later milestones. M0 ships a minimal
// NavigationSplitView placeholder plus a Settings scene so the target
// builds, launches, and reflects the sidebar sections from PLAN.md §3 / §5.

import SwiftUI

@main
struct InterlinedListApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
