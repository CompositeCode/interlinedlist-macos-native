// SettingsRootView
//
// The native Settings scene root (PLAN.md §5 — "native Settings scene
// (⌘,) — Account, Identities, Posting defaults, Subscription"). M6 lands
// the "Linked accounts" pane (browser-handoff OAuth linking); the other
// panes remain placeholders pending M7 (account, posting defaults,
// subscription).
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

            AccountSettingsPane()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - AccountSettingsPane
//
// Placeholder for the M7 account pane (email change, account deletion,
// avatar). Kept minimal so the Settings window has a second tab and the
// "Linked accounts" pane isn't the lone tab.
private struct AccountSettingsPane: View {
    var body: some View {
        Form {
            Section("Account") {
                Text("Account settings (email, avatar, deletion) ship in a later release.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsRootView()
}
