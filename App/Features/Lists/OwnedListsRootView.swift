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
    @State private var rowsViewModel: ListRowsViewModel?
    @State private var showsNewListSheet: Bool = false
    @State private var showsSchemaEditor: Bool = false
    @State private var showsWatchers: Bool = false
    @State private var showsShareLinks: Bool = false
    @State private var showsConnections: Bool = false
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
                    if let selected = viewModel.selectedList, let rowsVM = rowsViewModel {
                        ListRowsView(list: selected, viewModel: rowsVM)
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

                Button {
                    showsSchemaEditor = true
                } label: {
                    Label("Edit Schema", systemImage: "tablecells")
                }
                .disabled(viewModel.selectedListID == nil)

                Button {
                    showsWatchers = true
                } label: {
                    Label("Watchers", systemImage: "person.2")
                }
                .disabled(viewModel.selectedListID == nil)
                .help("Manage who can see and edit this list")

                Button {
                    showsShareLinks = true
                } label: {
                    Label("Share Links", systemImage: "link.badge.plus")
                }
                .disabled(viewModel.selectedListID == nil)
                .help("Create and manage shareable links for this list")

                Button {
                    showsConnections = true
                } label: {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(viewModel.selectedListID == nil)

                Button {
                    showsIssues = true
                } label: {
                    Label("Issues", systemImage: "ladybug")
                }
                .disabled(viewModel.selectedListGitHubRepo == nil)
                .help("Browse and create GitHub issues for this list")
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
        .sheet(isPresented: $showsShareLinks) {
            if let environment, let listId = viewModel.selectedListID {
                ShareLinksView(target: .list(id: listId), environment: environment)
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
            if let environment, let repo = viewModel.selectedListGitHubRepo {
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
            // Web-parity (work-consolidation.md G6) — folder tree above the lists.
            // Self-contained section that owns its own folders view model.
            ListFoldersSectionView()

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
        }
        .listStyle(.sidebar)
        .refreshable {
            await viewModel.refresh()
        }
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
