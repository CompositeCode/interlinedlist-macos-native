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

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: OwnedListsViewModel?
    @State private var showsNewListSheet: Bool = false
    @State private var showsSchemaEditor: Bool = false
    @State private var showsWatchers: Bool = false
    @State private var showsConnections: Bool = false
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
            if viewModel == nil, let environment {
                let model = OwnedListsViewModel(lists: environment.lists)
                viewModel = model
                await model.initialLoad()
                await subscribeToEventBus(viewModel: model, bus: environment.listsEventBus)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewListSheet)) { _ in
            showsNewListSheet = true
        }
    }

    @ViewBuilder
    private func content(viewModel: OwnedListsViewModel) -> some View {
        NavigationSplitView {
            sidebar(viewModel: viewModel)
        } content: {
            if let selected = viewModel.selectedList, let environment {
                ListRowsView(list: selected, environment: environment)
            } else {
                placeholderSelectListState
            }
        } detail: {
            if let environment, let selected = viewModel.selectedList {
                RowInspectorView(listId: selected.id, environment: environment)
            } else {
                Text("Select a row to inspect")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("My Lists")
        .toolbar {
            ToolbarItemGroup {
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
                    Label("Share", systemImage: "person.2")
                }
                .disabled(viewModel.selectedListID == nil)

                Button {
                    showsConnections = true
                } label: {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(viewModel.selectedListID == nil)
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
        .sheet(isPresented: $showsConnections) {
            if let environment, let listId = viewModel.selectedListID {
                ListConnectionsView(
                    listId: listId,
                    knownLists: viewModel.lists_loaded,
                    environment: environment
                )
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
            if viewModel.lists_loaded.isEmpty, viewModel.isLoading {
                ProgressView()
                    .accessibilityLabel("Loading lists")
                    .frame(maxWidth: .infinity)
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
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
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

    /// Subscribe to the lists event bus and feed each event into the
    /// view model's pure-local-mutation handler.
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
