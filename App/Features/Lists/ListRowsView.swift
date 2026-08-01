// ListRowsView
//
// The M3 rows table for an owned list (PLAN.md §6 M3 rows table).
// SwiftUI `Table` mode and `LazyVGrid` card mode, toggled from the
// View menu equivalent rendered as a Picker in the toolbar.

import SwiftUI
import InterlinedDomain

struct ListRowsView: View {

    let list: OwnedList
    let viewModel: ListRowsViewModel

    @State private var selection: Set<String> = []
    @State private var deletePending: Bool = false

    var body: some View {
        content(viewModel: viewModel)
            .navigationTitle(list.title)
    }

    @ViewBuilder
    private func content(viewModel: ListRowsViewModel) -> some View {
        VStack(spacing: 0) {
            toolbar(viewModel: viewModel)
            Divider()
            switch viewModel.viewMode {
            case .table:
                tableMode(viewModel: viewModel)
            case .cards:
                cardsMode(viewModel: viewModel)
            }
            if let error = viewModel.error {
                Divider()
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .padding(8)
            }
        }
        .confirmationDialog(
            "Delete selected rows?",
            isPresented: $deletePending
        ) {
            Button("Delete", role: .destructive) {
                let ids = selection
                Task {
                    await viewModel.deleteRows(ids: ids)
                    selection.removeAll()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func toolbar(viewModel: ListRowsViewModel) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.addRow() }
            } label: {
                Label("Add Row", systemImage: "plus")
            }

            Button {
                deletePending = true
            } label: {
                Label("Delete", systemImage: "minus")
            }
            .disabled(selection.isEmpty)

            Spacer()

            Picker("View", selection: Binding(
                get: { viewModel.viewMode },
                set: { viewModel.viewMode = $0 }
            )) {
                Label("Table", systemImage: "tablecells").tag(ListRowsViewModel.ViewMode.table)
                Label("Cards", systemImage: "rectangle.grid.2x2").tag(ListRowsViewModel.ViewMode.cards)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .accessibilityLabel("View mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tableMode(viewModel: ListRowsViewModel) -> some View {
        // Real SwiftUI `Table` with one typed column per schema field. The
        // dynamic-column `TableColumnForEach` needs macOS 14.4+; the app now
        // targets macOS 15, so the earlier `List`-of-cells fallback is retired.
        // `Table` has no per-row appearance hook, so pagination is a "Load more"
        // footer here (cards mode keeps scroll-to-load).
        let columns = effectiveColumns(viewModel)
        VStack(spacing: 0) {
            Table(viewModel.rows, selection: $selection) {
                TableColumnForEach(columns, id: \.self) { column in
                    TableColumn(column) { (row: ListRow) in
                        Text(row.fields[column]?.displayText ?? "")
                            .lineLimit(2)
                    }
                }
            }
            .onChange(of: selection) { _, newSelection in
                // Sync single-selection back into the view model so the
                // RowInspector can render.
                viewModel.selectedRowID = newSelection.first
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

    /// Ordered column set for the table: the schema-derived columns when
    /// present, else the sorted union of keys across loaded rows so a
    /// schemaless list still renders a sensible grid.
    private func effectiveColumns(_ viewModel: ListRowsViewModel) -> [String] {
        if !viewModel.columns.isEmpty { return viewModel.columns }
        var seen = Set<String>()
        var ordered: [String] = []
        for row in viewModel.rows {
            for key in row.fields.keys.sorted() where !seen.contains(key) {
                seen.insert(key)
                ordered.append(key)
            }
        }
        return ordered
    }

    @ViewBuilder
    private func cardsMode(viewModel: ListRowsViewModel) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
                spacing: 12
            ) {
                ForEach(viewModel.rows) { row in
                    Button {
                        viewModel.selectedRowID = row.id
                    } label: {
                        rowCard(row: row, columns: viewModel.columns)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rowAccessibilityLabel(row: row, columns: viewModel.columns))
                    .accessibilityHint("Selects this row for inspection")
                        .onAppear {
                            if shouldLoadMore(row, in: viewModel.rows) {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func rowCard(row: ListRow, columns: [String]) -> some View {
        let keys = columns.isEmpty ? row.fields.keys.sorted() : columns
        VStack(alignment: .leading, spacing: 4) {
            ForEach(keys, id: \.self) { key in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(key)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(row.fields[key]?.displayText ?? "")
                        .font(.ilBody())
                        .lineLimit(2)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(ILColor.surface2, in: RoundedRectangle(cornerRadius: ILMetric.radiusMd))
    }

    private func rowAccessibilityLabel(row: ListRow, columns: [String]) -> String {
        let keys = columns.isEmpty ? row.fields.keys.sorted() : columns
        let pairs = keys.compactMap { key -> String? in
            guard let value = row.fields[key]?.displayText, !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        return pairs.isEmpty ? "Row" : pairs.joined(separator: ", ")
    }

    private func shouldLoadMore(_ row: ListRow, in loaded: [ListRow]) -> Bool {
        guard let index = loaded.firstIndex(where: { $0.id == row.id }) else { return false }
        return index >= max(0, loaded.count - 5)
    }

}
