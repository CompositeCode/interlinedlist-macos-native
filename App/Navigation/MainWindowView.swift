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
import InterlinedDomain

/// Sidebar sections shown in the main window. Order mirrors PLAN.md §5
/// with the M5 addition of `Connections` (the followers/following/
/// requests roster panel — added in Wave 6.3 to surface the
/// dedicated Requests management UI alongside the inline tray rows).
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case search = "Search"
    case timeline = "Messages Timeline"
    case scheduled = "Scheduled"
    case notifications = "Notifications"
    case messages = "Direct Messages"
    case lists = "Lists"
    case documents = "Documents"
    case organizations = "Organizations"
    case profile = "Profile"
    case connections = "Connections"

    var id: String { rawValue }

    /// SF Symbol name for the row icon. Pure presentation hint; no semantics.
    var systemImage: String {
        switch self {
        case .search: return "magnifyingglass"
        case .timeline: return "house"
        case .scheduled: return "calendar"
        case .notifications: return "bell"
        case .messages: return "bubble.left.and.bubble.right"
        case .lists: return "list.bullet.rectangle"
        case .documents: return "doc.text"
        case .organizations: return "building.2"
        case .profile: return "person.crop.circle"
        case .connections: return "person.2"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var environment: AppEnvironment

    // Launch prefetch (PLAN.md §5, SWR Layer 3). The coordinator pre-warms
    // all four sections' view models (Lists, Documents, Scheduled,
    // Organizations) so each renders instantly from cache when the user
    // navigates to it, rather than waiting for its own .task to fire.
    @State private var prefetch: LaunchPrefetchCoordinator?

    @State private var selection: SidebarSection? = .timeline

    // M7 — Data Export sheet state. `pendingExportType` is set by each
    // `ExportMenuCommands` notification before `showExportSheet` is flipped
    // so `ExportView` receives the right initial type and can auto-start
    // the download (PLAN.md §6 M7).
    @State private var pendingExportType: ExportViewModel.ExportType? = nil
    @State private var showExportSheet = false

    // M5.x — Deep-link routing. When the user taps a system notification
    // banner and the target is a `.message(id:)`, we switch to the Timeline
    // sidebar and hand the message ID to `TimelineRootView` via a binding.
    // `TimelineRootView` sets its `NavigationStack` selection to that ID and
    // clears this state after handling so re-appearing timelines don't
    // re-navigate.
    @State private var pendingMessageDeepLinkID: String? = nil

    // Share Links (the-gaps.md G3) — when an opened share URL resolves to a
    // `ParsedShare`, `ShareLinkDeepLink` posts `.openShareLink` and this
    // state drives the `ResolveShareView` landing sheet.
    @State private var pendingShare: ParsedShare? = nil

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(SidebarSection.search.rawValue, systemImage: SidebarSection.search.systemImage)
                    .tag(SidebarSection.search)
                    .foregroundStyle(ILColor.onMasthead)
                Label(SidebarSection.timeline.rawValue, systemImage: SidebarSection.timeline.systemImage)
                    .tag(SidebarSection.timeline)
                    .foregroundStyle(ILColor.onMasthead)
                Label(SidebarSection.scheduled.rawValue, systemImage: SidebarSection.scheduled.systemImage)
                    .tag(SidebarSection.scheduled)
                    .foregroundStyle(ILColor.onMasthead)
                    .padding(.leading, 16)
                Label(SidebarSection.notifications.rawValue, systemImage: SidebarSection.notifications.systemImage)
                    .tag(SidebarSection.notifications)
                    .foregroundStyle(ILColor.onMasthead)
                Label(SidebarSection.messages.rawValue, systemImage: SidebarSection.messages.systemImage)
                    .tag(SidebarSection.messages)
                    .foregroundStyle(ILColor.onMasthead)
                Label(SidebarSection.lists.rawValue, systemImage: SidebarSection.lists.systemImage)
                    .tag(SidebarSection.lists)
                    .foregroundStyle(ILColor.onMasthead)
                Label(SidebarSection.documents.rawValue, systemImage: SidebarSection.documents.systemImage)
                    .tag(SidebarSection.documents)
                    .foregroundStyle(ILColor.onMasthead)
                Label(SidebarSection.organizations.rawValue, systemImage: SidebarSection.organizations.systemImage)
                    .tag(SidebarSection.organizations)
                    .foregroundStyle(ILColor.onMasthead)
                Label(SidebarSection.profile.rawValue, systemImage: SidebarSection.profile.systemImage)
                    .tag(SidebarSection.profile)
                    .foregroundStyle(ILColor.onMasthead)
                Label(SidebarSection.connections.rawValue, systemImage: SidebarSection.connections.systemImage)
                    .tag(SidebarSection.connections)
                    .foregroundStyle(ILColor.onMasthead)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(ILColor.masthead)
            .listItemTint(ILColor.primary)
            .navigationTitle("InterlinedList")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let selection {
                SidebarDetailDispatcher(
                    section: selection,
                    pendingMessageDeepLinkID: $pendingMessageDeepLinkID,
                    preloadedListsVM: prefetch?.listsVM,
                    preloadedFolderTreeVM: prefetch?.folderTreeVM,
                    preloadedDocumentsListVM: prefetch?.documentsListVM,
                    preloadedScheduledVM: prefetch?.scheduledVM,
                    preloadedOrganizationsVM: prefetch?.organizationsVM
                )
            } else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard prefetch == nil else { return }
            let coordinator = LaunchPrefetchCoordinator(environment: environment)
            prefetch = coordinator
            coordinator.warm()
        }
        // M5 menu deep-links — `NotificationsMenuCommands` and
        // `SocialMenuCommands` post these so the sidebar can swap
        // selection without the menu commands needing to know about
        // the view tree.
        .onReceive(NotificationCenter.default.publisher(for: .notificationsShow)) { _ in
            selection = .notifications
        }
        // Web-parity (the-gaps.md G5) — the ⌘F menu command posts
        // `.searchShow`; switch the sidebar to Search, then re-post
        // `.searchFocus` so the field takes focus once it is on screen.
        .onReceive(NotificationCenter.default.publisher(for: .searchShow)) { _ in
            selection = .search
            NotificationCenter.default.post(name: .searchFocus, object: nil)
        }
        // A document search hit has no typed deep-link target, so the
        // search view routes here to land the user on the Documents
        // section.
        .onReceive(NotificationCenter.default.publisher(for: .searchShowDocuments)) { _ in
            selection = .documents
        }
        // Direct Messages (the-gaps.md G1) — the ⌥⌘M menu command and the
        // profile "Message" button post `.directMessagesShow` to route the
        // sidebar to Messages. The `.directMessagesOpenThread` event that
        // may accompany it is observed by `DirectMessagesRootView` itself,
        // which selects the target conversation once it is on screen.
        .onReceive(NotificationCenter.default.publisher(for: .directMessagesShow)) { _ in
            selection = .messages
        }
        // M5.x — System notification banner deep-link. `AppDelegate` posts
        // `.notificationDeepLink` with the resolved `NotificationTarget` as
        // the `object` when the user taps a delivered banner. We switch the
        // sidebar to the appropriate section; message targets also set
        // `pendingMessageDeepLinkID` so `TimelineRootView` can push the
        // detail view via its own `NavigationStack`.
        .onReceive(NotificationCenter.default.publisher(for: .notificationDeepLink)) { note in
            guard let target = note.object as? NotificationTarget else { return }
            switch target {
            case .message(let id):
                selection = .timeline
                pendingMessageDeepLinkID = id
            case .list:
                selection = .lists
            case .user:
                // The user who acted is shown in the Connections panel
                // (followers / following / requests roster).
                selection = .connections
            case .organization:
                selection = .organizations
            case .unknown:
                // No typed target — fall back to the notifications tray
                // so the user sees the item that triggered the banner.
                selection = .notifications
            }
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
        // M7 — Export menu commands. Each notification maps to one ExportType;
        // the sheet auto-starts the corresponding download on appear.
        .onReceive(NotificationCenter.default.publisher(for: .exportMessages)) { _ in
            pendingExportType = .messages
            showExportSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportLists)) { _ in
            pendingExportType = .lists
            showExportSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportListDataRows)) { _ in
            pendingExportType = .listDataRows
            showExportSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportFollows)) { _ in
            pendingExportType = .follows
            showExportSheet = true
        }
        .sheet(isPresented: $showExportSheet, onDismiss: { pendingExportType = nil }) {
            ExportView(initialExportType: pendingExportType)
        }
        // Share Links (the-gaps.md G3) — an opened share URL posts
        // `.openShareLink` with the `ParsedShare`. Present the resolve/claim
        // landing; on a successful claim, route the sidebar to the resource
        // section so the user lands where they now have access.
        .onReceive(NotificationCenter.default.publisher(for: .openShareLink)) { note in
            guard let parsed = note.object as? ParsedShare else { return }
            pendingShare = parsed
        }
        .sheet(
            isPresented: Binding(
                get: { pendingShare != nil },
                set: { if !$0 { pendingShare = nil } }
            )
        ) {
            if let parsed = pendingShare {
                ResolveShareView(parsed: parsed, environment: environment) { _ in
                    selection = parsed.kind == .list ? .lists : .documents
                }
            }
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
    /// Binding supplied by `MainWindowView` when a `.message(id:)` deep-
    /// link fires. Only `.timeline` reads and clears it; every other case
    /// ignores it. The `Binding` lets `TimelineRootView` nil it out after
    /// handling so re-appearing timelines don't re-navigate.
    @Binding var pendingMessageDeepLinkID: String?

    /// Pre-warmed view models created by the `LaunchPrefetchCoordinator` on
    /// launch. Non-nil for all four warmed sections (Lists, Documents,
    /// Scheduled, Organizations); the remaining sections create their own
    /// view models inside their root views as before.
    var preloadedListsVM: OwnedListsViewModel? = nil
    var preloadedFolderTreeVM: FolderTreeViewModel? = nil
    var preloadedDocumentsListVM: DocumentsListViewModel? = nil
    var preloadedScheduledVM: ScheduledPostsViewModel? = nil
    var preloadedOrganizationsVM: OrganizationsListViewModel? = nil

    var body: some View {
        switch section {
        case .search:
            // Web-parity (the-gaps.md G5) — the global search surface
            // over messages / lists / documents. Routed from the sidebar
            // and from the ⌘F menu command.
            SearchRootView()
        case .timeline:
            TimelineRootView(pendingDeepLinkMessageID: $pendingMessageDeepLinkID)
        case .scheduled:
            // M6 (Wave 7.2) — the read-only Scheduled posts list lands
            // (PLAN.md §5 "Scheduled sidebar section", §6 M6). Replaces the
            // inline placeholder. Pre-warmed by the launch coordinator for
            // instant cache paint (SWR).
            ScheduledPostsRootView(preloadedViewModel: preloadedScheduledVM)
        case .notifications:
            NotificationsRootView()
        case .messages:
            // Web-parity (the-gaps.md G1) — the Direct Messages surface:
            // folder switcher → conversation list → thread. Routed from
            // the sidebar, the ⌥⌘M menu command, and the profile
            // "Message" button.
            DirectMessagesRootView()
        case .lists:
            // M3 (Wave 4.3) — sign-in routing:
            //   • Signed-in users get `OwnedListsRootView` (Lists CRUD).
            //   • Signed-out / unresolved sessions keep the M1 public
            //     browser. The router checks `currentUserStore` directly.
            ListsSidebarRouter(preloadedViewModel: preloadedListsVM)
        case .documents:
            // M4 (Wave 5.3) — Documents UI lands. The folder tree +
            // documents list + Markdown editor/Textual preview replace
            // the M0 placeholder. The placeholder remains in the
            // codebase as a preview fallback while we iterate.
            DocumentsRootView(
                preloadedFolderTree: preloadedFolderTreeVM,
                preloadedDocumentsList: preloadedDocumentsListVM
            )
        case .organizations:
            // M6 (Wave 7.3) — Organizations feature lands. The orgs list +
            // detail + member roster with role editing replace the M0
            // placeholder. Pre-warmed by the launch coordinator for instant
            // cache paint (SWR).
            OrganizationsRootView(preloadedViewModel: preloadedOrganizationsVM)
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

#Preview {
    MainWindowView()
        .environmentObject(AppEnvironment.live())
}
