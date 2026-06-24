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
//
// M5 adds the `@NSApplicationDelegateAdaptor` so the dock-tile badge
// can be written for unread notifications (PLAN.md §5 — "dock badge
// for unread"). This is the narrow AppKit exception documented in
// Decision 0005; the adapter is installed here so the AppDelegate's
// lifecycle aligns with the SwiftUI scene's. The notifications
// unread-badge coordinator subscribes to the event bus and writes
// the badge through the adapter.

import SwiftUI

@main
struct InterlinedListApp: App {

    /// Composition root constructed once for the app's lifetime.
    /// `@StateObject` so the same instance survives view-tree rebuilds.
    @StateObject private var environment = AppEnvironment.live()

    /// Narrow AppKit adapter (Decision 0005). Owned by the SwiftUI App
    /// scene; the only call site is the dock-badge writer inside the
    /// notifications coordinator.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Coordinator that turns notifications-bus events into dock-badge
    /// writes. `@State` so the launch `.task` can subscribe once and
    /// keep the same instance across view rebuilds.
    @State private var dockBadge: NotificationsUnreadBadgeCoordinator?

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
                    // M5 — subscribe to notifications events and write
                    // the dock-tile badge through the AppDelegate
                    // (Decision 0005). The coordinator listens on
                    // `NotificationsEventBus`; the tray view model
                    // posts `trayRefreshed(...)` after every successful
                    // load so the badge stays in sync without polling.
                    if dockBadge == nil {
                        let delegate = appDelegate
                        let coordinator = NotificationsUnreadBadgeCoordinator(
                            bus: environment.notificationsEventBus,
                            writeBadge: { @MainActor count in
                                delegate.updateDockBadge(unreadCount: count)
                            }
                        )
                        dockBadge = coordinator
                        coordinator.start()
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            ComposeCommands()
            ListMenuCommands()
            DocumentsMenuCommands()
            NotificationsMenuCommands()
            SocialMenuCommands()
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
