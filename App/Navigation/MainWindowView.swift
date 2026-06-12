// MainWindowView
//
// M0 placeholder for the app's main window. Renders a NavigationSplitView
// with the seven sidebar sections enumerated in PLAN.md §5 (Timeline,
// Scheduled, Notifications, Lists, Documents, Organizations, Profile) —
// static labels only; no behaviour. Real navigation routing arrives with
// the per-feature work in later waves.

import SwiftUI

/// Sidebar sections shown in the main window. Order mirrors PLAN.md §5.
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case timeline = "Timeline"
    case scheduled = "Scheduled"
    case notifications = "Notifications"
    case lists = "Lists"
    case documents = "Documents"
    case organizations = "Organizations"
    case profile = "Profile"

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
                PlaceholderDetailView(section: selection)
            } else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlaceholderDetailView: View {
    let section: SidebarSection

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(section.rawValue)
                .font(.title)
            Text("Coming soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.rawValue)
    }
}

#Preview {
    MainWindowView()
}
