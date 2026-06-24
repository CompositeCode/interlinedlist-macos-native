// InterlinedListApp
//
// App entry point. Constructs the composition root (`AppEnvironment`)
// once at launch and injects it into the view tree so every feature
// view model reads services from the environment rather than
// constructing them itself (PLAN.md §3).
//
// M2 adds the dedicated composer `Window` scene (PLAN.md §5 — "⌘N
// anywhere"), the ⌘N menu command (`ComposeCommands`), and a launch-
// time session restore so the ownership-gated edit / delete UI knows
// who the signed-in user is. Sign-out / re-sign-in still go through
// the Onboarding window (M0/M7).

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
                .task {
                    // Begin observing session state, then attempt a
                    // token-restore. Errors are swallowed at the launch
                    // boundary — a failed restore just leaves the UI in
                    // the signed-out projection (no current user → no
                    // ownership-gated UI), which is the correct safe
                    // default.
                    environment.currentUserStore.start()
                    _ = try? await environment.currentUserStore.restore()
                    // M4 — kick off one document sync cycle on launch
                    // (PLAN.md §6 M4 — "background sync engine; this is
                    // the app's offline backbone"). Errors are
                    // swallowed: a launch-time sync failure should not
                    // block the UI from rendering, and the toolbar's
                    // manual "Sync Now" button covers the recovery
                    // path. Detached so the launch surface returns
                    // immediately and the rest of `task` is not
                    // delayed by the network round-trip.
                    Task.detached { [environment] in
                        _ = try? await environment.documentSyncEngine.syncNow()
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            ComposeCommands()
            ListMenuCommands()
            DocumentsMenuCommands()
        }

        // Dedicated composer scene (PLAN.md §5). `Window` instead of
        // `WindowGroup` because we want a single composer at a time —
        // opening ⌘N twice should re-focus the existing window rather
        // than spawn a second one.
        Window("New Post", id: ComposeWindowID.newPost) {
            ComposerWindowView(mode: .newPost)
                .environmentObject(environment)
                .environment(\.appEnvironment, environment)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
