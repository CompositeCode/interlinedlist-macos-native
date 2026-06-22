// InterlinedListApp
//
// App entry point. Constructs the composition root (`AppEnvironment`)
// once at launch and injects it into the view tree so every feature
// view model reads services from the environment rather than
// constructing them itself (PLAN.md §3).
//
// The full scene graph (compose window, document windows, onboarding)
// is wired up in later milestones. M1 ships a NavigationSplitView with
// a real Timeline detail and placeholders for the remaining six
// sidebar sections, plus a Settings placeholder scene.

import SwiftUI

@main
struct InterlinedListApp: App {

    /// Composition root constructed once for the app's lifetime.
    /// `@StateObject` so the same instance survives view-tree rebuilds.
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(environment)
                .environment(\.appEnvironment, environment)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
