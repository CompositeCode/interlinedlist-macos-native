// OwnedListsRootView
//
// The M3 authenticated lists root (PLAN.md §6 M3). A
// `NavigationSplitView`-shaped content for the sidebar's `.lists`
// route: a sidebar of the user's lists (with nesting), the rows
// table for the selected list, and a right-side row inspector when
// a row is selected.
//
// Ownership gating: this view is only chosen when the
// `CurrentUserStore` reports a signed-in user. The `ListsRouter`
// (defined in `ListsSidebarRouter.swift`) routes signed-out users
// to the M1 public `ListsBrowserView`.

import SwiftUI
import InterlinedDomain

struct OwnedListsRootView: View {

    /// Pre-warmed view model supplied by `MainWindowView`. When non-nil
    /// the view skips creation and `initialLoad`; it still subscribes to
    /// the event bus so cross-window mutations land correctly.
    var preloadedViewModel: OwnedListsViewModel? = nil

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: OwnedListsViewModel?
    /// Drives the "Shared with me" sidebar section — lists other people own
    /// and gave this account access to (work-consolidation.md G23 / issue #48).
    /// A separate view model so a failing `GET /api/lists/watching` scopes its
    /// error to that section and leaves the owned lists rendering.
    @State private var watchedViewModel: WatchedListsViewModel?
    @State private var rowsViewModel: ListRowsViewModel?
    @State private var showsNewListSheet: Bool = false
    /// Drives the "Draft with AI" sheet (work-consolidation.md G15).
    @State private var showsAIListSheet = false

    /// Drives the "Create from…" sheet for the selected list
    /// (work-consolidation.md G16).
    @State private var showsCreateFromList = false
    @State private var showsSchemaEditor: Bool = false
    @State private var showsWatchers: Bool = false
    @State private var showsShareLinks: Bool = false
    @State private var showsInvites: Bool = false
    @State private var showsVisibility: Bool = false
    @State private var showsConnections: Bool = false
    @State private var showsContributors: Bool = false
    @State private var showsIssues: Bool = false
    @State private var listIDPendingDelete: String?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                unconfiguredState
            }
        }
        .task {
            guard let environment else { return }
            if viewModel == nil {
                let model: OwnedListsViewModel
                if let preloaded = preloadedViewModel {
                    // Pre-warmed by the launch coordinator — its cache-first
                    // load is already in flight / done; don't refetch here.
                    model = preloaded
                } else {
                    model = OwnedListsViewModel(lists: environment.lists)
                    await model.initialLoad()
                }
                viewModel = model
                await subscribeToEventBus(viewModel: model, bus: environment.listsEventBus)
            } else if let model = viewModel, model.shouldRefresh {
                // Re-appearance past the freshness TTL — revalidate; within
                // the TTL we trust the cache and skip the network.
                await model.refresh()
            }

            // "Shared with me" loads independently of the owned lists above,
            // and on its own TTL, so neither section can block or blank the
            // other (issue #48 acceptance criteria).
            if watchedViewModel == nil {
                let watched = WatchedListsViewModel(lists: environment.lists)
                watchedViewModel = watched
                await watched.load()
                await subscribeWatchedEventBus(viewModel: watched, bus: environment.listsEventBus)
            } else if let watched = watchedViewModel, watched.shouldRefresh {
                await watched.load()
            }
        }
        .task(id: viewModel?.selectedListID) {
            rowsViewModel = nil
            guard let environment, let listId = viewModel?.selectedListID else { return }
            let model = ListRowsViewModel(
                lists: environment.lists,
                eventBus: environment.listsEventBus,
                listId: listId
            )
            rowsViewModel = model
            await model.initialLoad()
            await subscribeRowsEventBus(viewModel: model, bus: environment.listsEventBus)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewListSheet)) { _ in
            showsNewListSheet = true
        }
    }

    @ViewBuilder
    private func content(viewModel: OwnedListsViewModel) -> some View {
        // A single `NavigationStack` hosting an `HSplitView`, not a nested
        // `NavigationSplitView`: this view lives inside `MainWindowView`'s
        // outer split view, and nesting a second `NavigationSplitView` there
        // leaves a dead gap and a non-resizable, non-filling rows column.
        // `HSplitView` packs the three panes edge-to-edge with draggable
        // dividers; the rows column carries `maxWidth: .infinity` so it
        // absorbs the free space in the center. (Mirrors the DirectMessages
        // root, which uses the same pattern for the same reason.)
        NavigationStack {
            HSplitView {
                sidebar(viewModel: viewModel)
                    .frame(minWidth: 220, idealWidth: 260)

                Group {
                    // The sidebar's single selection spans both sections, so
                    // the rows pane resolves it against the owned lists first
                    // and the shared-with-me lists second.
                    if let selected = viewModel.selectedList, let rowsVM = rowsViewModel {
                        ListRowsView(list: selected, viewModel: rowsVM)
                    } else if let watched = selectedWatchedList(viewModel: viewModel), let rowsVM = rowsViewModel {
                        // A `watcher`-role share is read-only: hide the row
                        // write affordances rather than letting them 403.
                        ListRowsView(list: watched.list, viewModel: rowsVM, isReadOnly: !watched.canEdit)
                    } else {
                        placeholderSelectListState
                    }
                }
                .frame(minWidth: 420, maxWidth: .infinity)

                RowInspectorView(viewModel: rowsViewModel)
                    .frame(minWidth: 280, idealWidth: 340)
            }
        }
        .navigationTitle("My Lists")
        .toolbar {
            ToolbarItemGroup {
                // Stale-while-revalidate: a subtle spinner while a background
                // refresh runs over cached rows already on screen. The
                // full-screen sidebar spinner only shows on a cold start.
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .help("Refreshing lists…")
                }

                Button {
                    showsNewListSheet = true
                } label: {
                    Label("New List", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.shift, .command])
                .help("Create a new list")

                // Draft a list with AI (work-consolidation.md G15). Sits beside
                // New List because it produces the same thing by another route.
                Button {
                    showsAIListSheet = true
                } label: {
                    Label("Draft with AI", systemImage: "sparkles")
                }
                .help("Describe a list and let AI draft its columns and starter rows")

                // "Create from…" over the selected list (work-consolidation.md G16).
                Button {
                    showsCreateFromList = true
                } label: {
                    Label("Create from\u{2026}", systemImage: "plus.rectangle.on.folder")
                }
                .disabled(viewModel.selectedListID == nil)
                .help("Turn this list into a document, or into another list")

                Button {
                    Task {
                        if let id = viewModel.selectedListID {
                            await viewModel.refreshList(id: id)
                        } else {
                            await viewModel.refresh()
                        }
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.selectedListID != nil && !viewModel.canRefreshSelectedList)
                .help(viewModel.canRefreshSelectedList
                      ? "Refresh from GitHub source"
                      : "Refresh lists")

                // Owner-only actions gate on an *owned* selection, not merely
                // on "something is selected": every route behind them is
                // owner-only server-side, so leaving them live for a list
                // someone shared with you renders an enabled-but-broken
                // control (work-consolidation.md G23).
                Button {
                    showsSchemaEditor = true
                } label: {
                    Label("Edit Schema", systemImage: "tablecells")
                }
                .disabled(viewModel.selectedList == nil)

                Button {
                    showsWatchers = true
                } label: {
                    Label("Watchers", systemImage: "person.2")
                }
                .disabled(viewModel.selectedList == nil)
                .help("Manage who can see and edit this list")

                // Contributors is readable by anyone with access, so it stays
                // enabled for a shared list too.
                Button {
                    showsContributors = true
                } label: {
                    Label("Contributors", systemImage: "person.3")
                }
                .disabled(viewModel.selectedListID == nil)
                .help("See who has added and edited rows on this list")

                Button {
                    showsShareLinks = true
                } label: {
                    Label("Share Links", systemImage: "link.badge.plus")
                }
                .disabled(viewModel.selectedList == nil)
                .help("Create and manage shareable links for this list")

                Button {
                    showsInvites = true
                } label: {
                    Label("Invite by Email", systemImage: "envelope")
                }
                .disabled(viewModel.selectedList == nil)
                .help("Invite people to this list by email")

                Button {
                    showsVisibility = true
                } label: {
                    Label("Make Public", systemImage: "globe")
                }
                .disabled(viewModel.selectedList == nil)
                .help("Control whether anyone with the link can view this list")

                Button {
                    showsConnections = true
                } label: {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(viewModel.selectedList == nil)

                Button {
                    showsIssues = true
                } label: {
                    Label("Issues", systemImage: "ladybug")
                }
                // Prefer the row-derived repo (the authoritative backing signal
                // today) over the list-level field, which stays nil until the
                // backend surfaces `githubSource` on lists (P3-C). This is what
                // finally makes the already-built issue browser reachable.
                .disabled((rowsViewModel?.gitHubRepo ?? viewModel.selectedListGitHubRepo) == nil)
                .help("Browse and create GitHub issues for this list")
            }
        }
        .sheet(isPresented: $showsCreateFromList) {
            if let environment, let listId = viewModel.selectedListID {
                CreateFromSheet(
                    source: .lists(ids: [listId]),
                    environment: environment,
                    initialOutput: .document
                ) { _ in
                    Task { await viewModel.refresh() }
                }
            }
        }
        .sheet(isPresented: $showsAIListSheet) {
            if let environment {
                AIListTemplateSheet(environment: environment) {
                    // The drafted list was created server-side; reload so it
                    // appears without the user having to refresh by hand.
                    await viewModel.refresh()
                }
            }
        }
        .sheet(isPresented: $showsNewListSheet) {
            if let environment {
                NewListSheetView(
                    environment: environment,
                    parentCandidates: viewModel.lists_loaded
                )
            }
        }
        .sheet(isPresented: $showsSchemaEditor) {
            if let environment, let listId = viewModel.selectedListID {
                SchemaEditorView(listId: listId, environment: environment)
            }
        }
        .sheet(isPresented: $showsWatchers) {
            if let environment, let listId = viewModel.selectedListID {
                WatchersView(listId: listId, environment: environment)
            }
        }
        .sheet(isPresented: $showsContributors) {
            if let environment, let listId = viewModel.selectedListID {
                ContributorsView(listId: listId, environment: environment)
            }
        }
        .sheet(isPresented: $showsShareLinks) {
            if let environment, let listId = viewModel.selectedListID {
                ShareLinksView(target: .list(id: listId), environment: environment)
            }
        }
        .sheet(isPresented: $showsInvites) {
            if let environment, let listId = viewModel.selectedListID {
                InvitesView(target: .list(id: listId), environment: environment)
            }
        }
        .sheet(isPresented: $showsVisibility) {
            if let environment, let list = viewModel.selectedList {
                VisibilityView(
                    target: .list(id: list.id),
                    environment: environment,
                    initialIsPublic: list.visibility.isPubliclyVisible
                )
            }
        }
        .sheet(isPresented: $showsConnections) {
            if let environment, let listId = viewModel.selectedListID {
                ListConnectionsView(
                    listId: listId,
                    knownLists: viewModel.lists_loaded,
                    environment: environment
                )
            }
        }
        .sheet(isPresented: $showsIssues) {
            if let environment, let repo = rowsViewModel?.gitHubRepo ?? viewModel.selectedListGitHubRepo {
                GitHubIssuesView(repo: repo, environment: environment)
            }
        }
        .confirmationDialog(
            "Delete this list?",
            isPresented: Binding(
                get: { listIDPendingDelete != nil },
                set: { if !$0 { listIDPendingDelete = nil } }
            ),
            presenting: listIDPendingDelete
        ) { id in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteList(id: id)
                    listIDPendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                listIDPendingDelete = nil
            }
        } message: { _ in
            Text("Deleting a list also removes its rows, schema, and connections.")
        }
    }

    @ViewBuilder
    private func sidebar(viewModel: OwnedListsViewModel) -> some View {
        List(selection: Binding(
            get: { viewModel.selectedListID },
            set: { viewModel.select(id: $0) }
        )) {
            Section("Lists") {
            if viewModel.lists_loaded.isEmpty, viewModel.isLoading {
                ProgressView()
                    .accessibilityLabel("Loading lists")
                    .frame(maxWidth: .infinity)
            } else if let error = viewModel.error, viewModel.lists_loaded.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't load lists", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.refresh() }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            } else if viewModel.lists_loaded.isEmpty {
                Text("No lists yet — create one to begin.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.roots()) { list in
                    OwnedListSidebarRow(
                        list: list,
                        viewModel: viewModel,
                        onDeleteRequested: { listIDPendingDelete = $0.id }
                    )
                }
            }
            } // Section("Lists")

            sharedWithMeSection
        }
        .listStyle(.sidebar)
        .refreshable {
            await viewModel.refresh()
            await watchedViewModel?.load()
        }
    }

    /// The "Shared with me" sidebar section — lists other people own and gave
    /// this account access to (work-consolidation.md G23 / issue #48). Mirrors
    /// the web's `/lists` datagrid columns: title, owner, and your role.
    ///
    /// The section is omitted entirely when nothing is shared and nothing went
    /// wrong, so an account nobody shares with sees the sidebar it always saw.
    @ViewBuilder
    private var sharedWithMeSection: some View {
        if let watched = watchedViewModel {
            if let error = watched.error, watched.watched.isEmpty {
                Section("Shared with me") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Couldn't load shared lists", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await watched.load() }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            } else if watched.watched.isEmpty {
                // Nothing shared and no error: render nothing rather than an
                // empty-state row that would sit there forever.
                EmptyView()
            } else {
                // Grouped by the caller's role so "what I can edit" reads
                // apart from "what I can only look at".
                ForEach(watched.groupedByRole, id: \.role) { group in
                    Section("Shared with me — \(group.role.label)") {
                        ForEach(group.lists) { entry in
                            WatchedListSidebarRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                }
                if watched.hasMore {
                    Button("Load more shared lists") {
                        Task { await watched.loadMore() }
                    }
                    .font(.caption)
                }
            }
        }
    }

    /// Resolves the sidebar selection against the shared-with-me lists. Only
    /// consulted after the owned lists miss, so an id can never resolve twice.
    private func selectedWatchedList(viewModel: OwnedListsViewModel) -> WatchedList? {
        watchedViewModel?.list(withID: viewModel.selectedListID)
    }

    private var placeholderSelectListState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Select a list")
                .font(.ilSubtitle())
            Text("Choose a list from the sidebar to view its rows.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Lists unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func subscribeToEventBus(
        viewModel: OwnedListsViewModel,
        bus: ListsEventBus
    ) async {
        Task { [weak viewModel] in
            for await event in bus.events() {
                guard let viewModel else { return }
                viewModel.apply(event: event)
            }
        }
    }

    private func subscribeWatchedEventBus(
        viewModel: WatchedListsViewModel,
        bus: ListsEventBus
    ) async {
        Task { [weak viewModel] in
            for await event in bus.events() {
                guard let viewModel else { return }
                viewModel.apply(event: event)
            }
        }
    }

    private func subscribeRowsEventBus(
        viewModel: ListRowsViewModel,
        bus: ListsEventBus
    ) async {
        Task { [weak viewModel] in
            for await event in bus.events() {
                guard let viewModel else { return }
                viewModel.apply(event: event)
            }
        }
    }
}

// MARK: - Shared-with-me sidebar row

/// One row in the "Shared with me" section: the list title, who owns it, and
/// the caller's role — the same three columns the web's `/lists` datagrid
/// shows (work-consolidation.md G23).
private struct WatchedListSidebarRow: View {
    let entry: WatchedList

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.rectangle.stack")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let owner = entry.owner {
                        Text(owner.displayLabel)
                            .lineLimit(1)
                    }
                    // The parent projection is a label only — a shared child
                    // does not imply access to its parent, so it never links.
                    if let parentTitle = entry.parentTitle {
                        Text("· in \(parentTitle)")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let owner = entry.owner.map { ", owned by \($0.displayLabel)" } ?? ""
        return "\(entry.title)\(owner), your access: \(entry.role.label)"
    }
}

// MARK: - Sidebar row

private struct OwnedListSidebarRow: View {
    let list: OwnedList
    let viewModel: OwnedListsViewModel
    let onDeleteRequested: (OwnedList) -> Void

    var body: some View {
        let children = viewModel.children(of: list.id)
        Group {
            if children.isEmpty {
                row
            } else {
                DisclosureGroup {
                    ForEach(children) { child in
                        OwnedListSidebarRow(
                            list: child,
                            viewModel: viewModel,
                            onDeleteRequested: onDeleteRequested
                        )
                    }
                } label: {
                    row
                }
            }
        }
        .tag(list.id)
    }

    private var row: some View {
        HStack(spacing: 6) {
            Image(systemName: list.gitHubSource != nil
                  ? "list.bullet.rectangle.portrait.fill"
                  : "list.bullet.rectangle")
                .foregroundStyle(list.gitHubSource != nil ? Color.accentColor : .primary)
                .accessibilityHidden(true)
            Text(list.title)
                .lineLimit(1)
            if list.gitHubSource != nil {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("GitHub-backed list")
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(list.gitHubSource != nil ? "\(list.title), GitHub-backed list" : list.title)
        .contextMenu {
            Button(role: .destructive) {
                onDeleteRequested(list)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
