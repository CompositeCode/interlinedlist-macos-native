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

/// The Settings tabs, as a selectable identity.
///
/// Exists so a caller outside the Settings scene can say *which* pane it wants
/// (GitHub #45). `SettingsLink` opens the window and cannot address a tab, so
/// the sidebar's "Integrations" row stores the target here first and the scene
/// opens on it.
enum SettingsTab: String, CaseIterable, Hashable {
    case linkedAccounts
    // Integrations (#47/PR #93) and Profile (#46/PR #92) landed after this enum
    // did — PR #94 wrote it against a `dev` that had neither. Their tabs existed
    // without tags until this merge, which under `TabView(selection:)` means
    // they could not be programmatically selected at all.
    case integrations
    case account
    case profile
    case preferences
    case blockedAndMuted
    case notifications
    case security
    case devices
    case documentSync
    case crashReporting
}

struct SettingsRootView: View {

    /// The open tab, persisted so it survives the window closing — which is
    /// also what lets another surface preselect it before opening.
    @AppStorage("settings.selectedTab") private var selectedTab: SettingsTab = .linkedAccounts

    var body: some View {
        TabView(selection: $selectedTab) {
            LinkedAccountsView()
                .tabItem {
                    Label("Linked accounts", systemImage: "link")
                }
                .tag(SettingsTab.linkedAccounts)

            // Manage every connected provider in one place — verify, disconnect,
            // and GitHub org access (GitHub #47 / G33). Linking itself stays in
            // the Linked accounts pane, which owns the OAuth session.
            IntegrationsView()
                .tabItem {
                    Label("Integrations", systemImage: "app.connected.to.app.below.fill")
                }
                .tag(SettingsTab.integrations)

            AccountSettingsView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .tag(SettingsTab.account)

            // Identity: display name, bio, avatar, theme and the per-message
            // character cap (GitHub #46 / G34). Until this pane existed the
            // display name and bio were uneditable from macOS entirely.
            ProfileSettingsView()
                .tabItem {
                    Label("Profile", systemImage: "person.text.rectangle")
                }
                .tag(SettingsTab.profile)

            // Server-synced account preferences (work-consolidation.md — settings
            // storage) via `POST /api/user/update`.
            PreferencesView()
                .tabItem {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }
                .tag(SettingsTab.preferences)

            // Web-parity (work-consolidation.md G2) — blocked / muted account
            // management with inline unblock / unmute.
            BlockedAndMutedView()
                .tabItem {
                    Label("Blocked & Muted", systemImage: "hand.raised")
                }
                .tag(SettingsTab.blockedAndMuted)

            // Server-driven notification event catalogue (work-consolidation.md G18).
            NotificationPreferencesView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(SettingsTab.notifications)

            // Active sessions with per-row revoke (work-consolidation.md G19).
            SecuritySessionsView()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
                .tag(SettingsTab.security)

            // Synced-settings device registry (work-consolidation.md G17) — the
            // machines registered under this app's key.
            DevicesView()
                .tabItem {
                    Label("Devices", systemImage: "desktopcomputer")
                }
                .tag(SettingsTab.devices)

            // Document sync agent (work-consolidation.md §3b) — enable the background helper
            // that mirrors documents to a local folder for Obsidian.
            DocumentSyncSettingsView()
                .tabItem {
                    Label("Document Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsTab.documentSync)

            // Crash reporting (GitHub issue #29) — opt in to being asked, on
            // the launch after a crash, whether to file a GitHub issue. A
            // native-only, machine-local preference, so it is not part of the
            // server-synced Preferences pane above.
            CrashReportingSettingsView()
                .tabItem {
                    Label("Crash Reporting", systemImage: "ladybug")
                }
                .tag(SettingsTab.crashReporting)
        }
        .frame(width: 620, height: 520)
    }
}

#Preview {
    SettingsRootView()
}
