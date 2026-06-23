// ListDetailView
//
// Detail screen for a single public list. Loads metadata + the first
// page of rows and renders them as a `List` of key/value cards, one
// card per row (PLAN.md §1 "Structured lists", §6 M1).
//
// Why a card list and not a `Table` in M1:
//
//   - `ListRow.fields` is loose-typed (`[String: ListCellValue]`) until
//     the M3 schema-DSL parser lands, so columns are only derivable
//     from observed row data — not from a static schema.
//   - SwiftUI `Table` requires either statically-keyed `TableColumn`s
//     or `TableColumnForEach`, and the latter is macOS 14.4+. The
//     project targets macOS 14.0, so the dynamic-column path is not
//     yet available to us.
//
// The typed-per-column schema editor and full Table-with-typed-columns
// land in M3 alongside the schema DSL parser. Here we render what the
// loose `ListCellValue` projection exposes — `displayText` for every
// cell — so the read-only browser ships without the parser.

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
            rowsContent(viewModel: viewModel)
        }
        .refreshable {
            await viewModel.refresh()
        }
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
                        .font(.title2.weight(.semibold))
                    if detail.visibility == .private {
                        Label("Private", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Private list")
                    }
                    Spacer()
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let description = detail.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let schema = detail.schemaDescription, !schema.isEmpty {
                    Label(schema, systemImage: "tablecells")
                        .font(.caption)
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
            rowsCardList(viewModel: viewModel, columns: viewModel.columns)
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
                        .font(.body)
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
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No rows")
                .font(.headline)
            Text("This list has no rows yet.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: ListDetailViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load this list")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
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
                .font(.headline)
            Text("Create a copy of this list in your account.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Name", text: $savedListName)
                .textFieldStyle(.roundedBorder)
            if let viewModel,
               case .saved(let list) = viewModel.saveState {
                Text("Saved as \"\(list.title)\".")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if let viewModel,
                      case .failed(let message) = viewModel.saveState {
                Text(message)
                    .font(.caption)
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
