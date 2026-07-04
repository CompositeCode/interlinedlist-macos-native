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
// who the signed-in user is.
//
// M5 adds the `@NSApplicationDelegateAdaptor` so the dock-tile badge
// can be written for unread notifications (PLAN.md §5 — "dock badge
// for unread"). This is the narrow AppKit exception documented in
// Decision 0005; the adapter is installed here so the AppDelegate's
// lifecycle aligns with the SwiftUI scene's. The notifications
// unread-badge coordinator subscribes to the event bus and writes
// the badge through the adapter.
//
// M7 adds the Onboarding window: the `WindowGroup` body switches
// between `OnboardingView` and `MainWindowView` based on whether a
// `CurrentUser` has resolved. `AppRootView` observes `CurrentUserStore`
// (an `@Observable` class) so the switch is reactive — sign-in makes
// the user non-nil and SwiftUI re-renders `MainWindowView` in place.

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
            AppRootView(store: environment.currentUserStore)
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
            AccountMenuCommands()
            ComposeCommands()
            ListMenuCommands()
            DocumentsMenuCommands()
            NotificationsMenuCommands()
            SocialMenuCommands()
            // M7 — CSV exports via File > Export submenu (PLAN.md §6 M7).
            ExportMenuCommands()
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
            SettingsRootView()
                .environmentObject(environment)
                .environment(\.appEnvironment, environment)
        }
    }
}

// MARK: - AppRootView

/// Session-aware root switcher (M7). Reads `CurrentUserStore.currentUser`
/// directly so SwiftUI's `@Observable` tracking re-renders the window
/// content when sign-in resolves or sign-out clears the user. A separate
/// view struct is necessary because `@Observable` dependency tracking
/// operates on `View.body`, not on the `Scene.body` closure.
///
/// Also handles the `accountSignOut` notification posted by
/// `AccountMenuCommands` — the notification pattern keeps the Commands
/// struct dependency-free while this view, which always lives in the
/// view tree, holds the async session reference.
private struct AppRootView: View {
    /// `CurrentUserStore` is `@Observable`; reading `store.currentUser`
    /// in `body` registers a dependency that fires when the user changes.
    let store: CurrentUserStore

    @Environment(\.appEnvironment) private var environment

    var body: some View {
        Group {
            if store.currentUser != nil {
                MainWindowView()
            } else {
                OnboardingView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountSignOut)) { _ in
            guard let environment else { return }
            Task { try? await environment.session.signOut() }
        }
    }
}
