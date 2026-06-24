// MainWindowView
//
// The app's main window: a `NavigationSplitView` with the seven
// sidebar sections enumerated in PLAN.md §5 (Timeline, Scheduled,
// Notifications, Lists, Documents, Organizations, Profile).
//
// The sidebar is fixed; the detail column is driven by the
// `SidebarDetailDispatcher` below, which switches on `SidebarSection`
// and returns the per-feature root view. Each feature owns its own
// folder under `App/Features/<Feature>/` and replaces its case in the
// dispatcher when it lands — every other line stays untouched.

import SwiftUI

/// Sidebar sections shown in the main window. Order mirrors PLAN.md §5
/// with the M5 addition of `Connections` (the followers/following/
/// requests roster panel — added in Wave 6.3 to surface the
/// dedicated Requests management UI alongside the inline tray rows).
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case timeline = "Timeline"
    case scheduled = "Scheduled"
    case notifications = "Notifications"
    case lists = "Lists"
    case documents = "Documents"
    case organizations = "Organizations"
    case profile = "Profile"
    case connections = "Connections"

    var id: String { rawValue }

    /// SF Symbol name for the row icon. Pure presentation hint; no semantics.
    var systemImage: String {
        switch self {
        case .timeline: return "house"
        case .scheduled: return "calendar"
        case .notifications: return "bell"
        case .lists: return "list.bullet.rectangle"
        case .documents: return "doc.text"
        case .organizations: return "building.2"
        case .profile: return "person.crop.circle"
        case .connections: return "person.2"
        }
    }
}

struct MainWindowView: View {
    @State private var selection: SidebarSection? = .timeline

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("InterlinedList")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let selection {
                SidebarDetailDispatcher(section: selection)
            } else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
            }
        }
        // M5 menu deep-links — `NotificationsMenuCommands` and
        // `SocialMenuCommands` post these so the sidebar can swap
        // selection without the menu commands needing to know about
        // the view tree.
        .onReceive(NotificationCenter.default.publisher(for: .notificationsShow)) { _ in
            selection = .notifications
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialShowFollowers)) { _ in
            selection = .connections
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialShowFollowing)) { _ in
            selection = .connections
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialShowRequests)) { _ in
            selection = .connections
        }
    }
}

// MARK: - SidebarDetailDispatcher
//
// Single switch that maps a sidebar section to its detail view. This is
// the *only* place feature roots are constructed for the main window.
//
// Extension contract for parallel feature agents:
//   - To wire up a new feature, change exactly one line in this switch
//     to point at the new feature root (e.g. `case .lists: ListsBrowserView()`).
//   - Do not add cross-cutting state here. Anything richer than "swap
//     one case to its new root view" belongs inside the feature folder.
//   - Cases that have not landed yet render their original
//     `*PlaceholderView` so the app keeps building.

private struct SidebarDetailDispatcher: View {
    let section: SidebarSection

    var body: some View {
        switch section {
        case .timeline:
            TimelineRootView()
        case .scheduled:
            // Scheduled posts ship in M6 with cross-posting (PLAN.md §6).
            // No dedicated folder exists yet; a tiny inline placeholder
            // stands in until the scheduled-posts UI lands. (Previously
            // this case reused `ComposePlaceholderView`; that file was
            // removed in Wave 3 once the real composer landed in a
            // dedicated window scene, so the stand-in is inline here.)
            ScheduledPlaceholderView()
        case .notifications:
            NotificationsRootView()
        case .lists:
            // M3 (Wave 4.3) — sign-in routing:
            //   • Signed-in users get `OwnedListsRootView` (Lists CRUD).
            //   • Signed-out / unresolved sessions keep the M1 public
            //     browser. The router checks `currentUserStore` directly.
            ListsSidebarRouter()
        case .documents:
            // M4 (Wave 5.3) — Documents UI lands. The folder tree +
            // documents list + Markdown editor/Textual preview replace
            // the M0 placeholder. The placeholder remains in the
            // codebase as a preview fallback while we iterate.
            DocumentsRootView()
        case .organizations:
            OrganizationsPlaceholderView()
        case .profile:
            ProfileRootView()
        case .connections:
            // M5 (Wave 6.3) — followers / following / requests panel.
            // Routed from the menu (`SocialMenuCommands`) and from
            // the sidebar.
            SocialRosterRootView()
        }
    }
}

// MARK: - ScheduledPlaceholderView
//
// Tiny stand-in for the Scheduled sidebar section, which ships in M6
// alongside cross-posting (PLAN.md §6 M6). Replaced when the real
// scheduled-posts UI lands.
private struct ScheduledPlaceholderView: View {
    var body: some View {
        Text("Scheduled")
            .font(.title)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppEnvironment.live())
}
