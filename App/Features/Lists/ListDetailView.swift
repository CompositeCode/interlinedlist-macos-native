// ListDetailView
//
// Detail screen for a single public list. Loads metadata + paged rows and
// renders them either as key/value cards or a real SwiftUI `Table` grid,
// toggled by a segmented control above the rows (work-consolidation.md §1b —
// bringing the owned-list grid to the read-only public browser).
//
// The dynamic-column `TableColumnForEach` needs macOS 14.4+; the app targets
// macOS 15, so the table path is available (the same path the owned
// `ListRowsView` uses). `ListRow.fields` is loose-typed
// (`[String: ListCellValue]`), so columns come from `ListDetailViewModel.columns`
// (the sorted union of row-field keys) rather than a static schema, and
// `displayText` renders every cell. `Table` has no per-row appearance hook, so
// the grid paginates with a "Load More" footer (cards keep scroll-to-load).

import SwiftUI
import InterlinedDomain

struct ListDetailView: View {

    let username: String
    let slug: String

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: ListDetailViewModel?
    @State private var saveSheetPresented: Bool = false
    @State private var savedListName: String = ""

    var body: some View {
        Group {
            if let viewModel {
                detailBody(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel?.detail?.title ?? "List")
        .toolbar {
            ToolbarItem {
                if let viewModel,
                   environment?.currentUserStore.currentUserID != nil,
                   viewModel.detail != nil {
                    Button {
                        savedListName = viewModel.detail?.title ?? ""
                        saveSheetPresented = true
                    } label: {
                        Label("Save to my lists", systemImage: "tray.and.arrow.down")
                    }
                }
            }
        }
        .sheet(isPresented: $saveSheetPresented) {
            saveSheet
        }
        .task {
            if viewModel == nil, let environment {
                let model = ListDetailViewModel(
                    lists: environment.lists,
                    username: username,
                    slug: slug,
                    eventBus: environment.listsEventBus
                )
                viewModel = model
                await model.load()
            }
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private func detailBody(viewModel: ListDetailViewModel) -> some View {
        VStack(spacing: 0) {
            header(viewModel: viewModel)
            Divider()
            if !viewModel.rows.isEmpty {
                viewModeBar(viewModel: viewModel)
            }
            rowsContent(viewModel: viewModel)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    /// A right-aligned segmented control to switch the rows between the card
    /// list and the `Table` grid (work-consolidation.md §1b). Shown only when
    /// there are rows to render.
    @ViewBuilder
    private func viewModeBar(viewModel: ListDetailViewModel) -> some View {
        HStack {
            Spacer()
            Picker("View", selection: Binding(
                get: { viewModel.viewMode },
                set: { viewModel.viewMode = $0 }
            )) {
                Label("Cards", systemImage: "rectangle.grid.2x2")
                    .tag(ListDetailViewModel.ViewMode.cards)
                Label("Table", systemImage: "tablecells")
                    .tag(ListDetailViewModel.ViewMode.table)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .fixedSize()
            .accessibilityLabel("View mode")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func header(viewModel: ListDetailViewModel) -> some View {
        if let detail = viewModel.detail {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(detail.title)
                        .font(.ilDisplay())
                    if detail.visibility == .private {
                        Label("Private", systemImage: "lock")
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Private list")
                    }
                    Spacer()
                    Text("@\(username)")
                        .font(.ilSubtitle())
                        .foregroundStyle(.secondary)
                }
                if let description = detail.description, !description.isEmpty {
                    Text(description)
                        .font(.ilSubtitle())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let schema = detail.schemaDescription, !schema.isEmpty {
                    Label(schema, systemImage: "tablecells")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Schema: \(schema)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func rowsContent(viewModel: ListDetailViewModel) -> some View {
        if let error = viewModel.error, viewModel.rows.isEmpty {
            errorState(error: error, viewModel: viewModel)
        } else if viewModel.rows.isEmpty, viewModel.isLoading {
            loadingState
        } else if viewModel.rows.isEmpty {
            emptyRowsState
        } else {
            switch viewModel.viewMode {
            case .cards:
                rowsCardList(viewModel: viewModel, columns: viewModel.columns)
            case .table:
                rowsTable(viewModel: viewModel)
            }
        }
    }

    /// The read-only `Table` grid — one column per derived field, `displayText`
    /// per cell, and a "Load More" footer for pagination (the grid has no
    /// per-row `.onAppear` hook). Mirrors the owned `ListRowsView` table.
    @ViewBuilder
    private func rowsTable(viewModel: ListDetailViewModel) -> some View {
        VStack(spacing: 0) {
            Table(viewModel.rows) {
                TableColumnForEach(viewModel.columns, id: \.self) { column in
                    TableColumn(column) { (row: ListRow) in
                        Text(row.fields[column]?.displayText ?? "")
                            .lineLimit(2)
                    }
                }
            }

            if viewModel.hasMore {
                Divider()
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Load More Rows")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading)
                .padding(8)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Load more rows")
            }
        }
    }

    // MARK: - Rendering modes

    @ViewBuilder
    private func rowsCardList(viewModel: ListDetailViewModel, columns: [String]) -> some View {
        List {
            ForEach(viewModel.rows) { row in
                rowCard(row: row, columns: columns)
                    .onAppear {
                        if shouldLoadMore(for: row, in: viewModel.rows) {
                            Task { await viewModel.loadMore() }
                        }
                    }
            }
            if viewModel.isLoading, !viewModel.rows.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading more rows")
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func rowCard(row: ListRow, columns: [String]) -> some View {
        // When `columns` was empty (no rows on screen yet at compute
        // time) fall back to the row's own field keys, sorted for a
        // deterministic render.
        let keys = columns.isEmpty ? row.fields.keys.sorted() : columns
        VStack(alignment: .leading, spacing: 4) {
            ForEach(keys, id: \.self) { key in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(key)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 80, alignment: .leading)
                    Text(row.fields[key]?.displayText ?? "")
                        .font(.ilBody())
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading rows…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyRowsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("No rows")
                .font(.ilSubtitle())
            Text("This list has no rows yet.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: ListDetailViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load this list")
                .font(.ilSubtitle())
            Text(error.localizedDescription)
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Save sheet

    @ViewBuilder
    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save to my lists")
                .font(.ilSubtitle())
            Text("Create a copy of this list in your account.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            TextField("Name", text: $savedListName)
                .textFieldStyle(.roundedBorder)
            if let viewModel,
               case .saved(let list) = viewModel.saveState {
                Text("Saved as \"\(list.title)\".")
                    .font(.ilMono(10))
                    .foregroundStyle(ILColor.primary)
            } else if let viewModel,
                      case .failed(let message) = viewModel.saveState {
                Text(message)
                    .font(.ilMono(10))
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    saveSheetPresented = false
                }
                Spacer()
                Button("Save") {
                    Task {
                        await viewModel?.saveToMyLists(suggestedName: savedListName)
                        if case .saved = viewModel?.saveState {
                            saveSheetPresented = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(savedListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 380)
    }

    // MARK: - Helpers

    private func shouldLoadMore(for row: ListRow, in loaded: [ListRow]) -> Bool {
        guard let index = loaded.firstIndex(where: { $0.id == row.id }) else { return false }
        return index >= max(0, loaded.count - 5)
    }
}
