// SettingsRootView
//
// The native Settings scene root (PLAN.md §5 — "native Settings scene
// (⌘,) — Account, Identities, Posting defaults, Subscription"). M6 lands
// the "Linked accounts" pane (browser-handoff OAuth linking); M7 lands
// the full "Account" pane (avatar, email change, account deletion).
//
// A `TabView` so each pane is an independent Settings tab the way macOS
// Settings windows conventionally present them.
//
// Per decision 0003 the view consumes only `InterlinedDomain`.

import SwiftUI

struct SettingsRootView: View {

    var body: some View {
        TabView {
            LinkedAccountsView()
                .tabItem {
                    Label("Linked accounts", systemImage: "link")
                }

            AccountSettingsView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }

            // Server-synced account preferences (work-consolidation.md — settings
            // storage) via `POST /api/user/update`.
            PreferencesView()
                .tabItem {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }

            // Web-parity (work-consolidation.md G2) — blocked / muted account
            // management with inline unblock / unmute.
            BlockedAndMutedView()
                .tabItem {
                    Label("Blocked & Muted", systemImage: "hand.raised")
                }

            // Document sync agent (work-consolidation.md §3b) — enable the background helper
            // that mirrors documents to a local folder for Obsidian.
            DocumentSyncSettingsView()
                .tabItem {
                    Label("Document Sync", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 560, height: 500)
    }
}

#Preview {
    SettingsRootView()
}
