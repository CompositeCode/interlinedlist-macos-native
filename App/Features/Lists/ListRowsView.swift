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

    @Environment(\.appEnvironment) private var environment
    @State private var selection: Set<String> = []
    @State private var deletePending: Bool = false
    /// Presents the GitHub issue browser/composer for a GitHub-backed list —
    /// the row-creation route for lists whose rows sync from GitHub.
    @State private var showsIssues: Bool = false

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
            case .entity:
                entityMode(viewModel: viewModel)
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
        .sheet(isPresented: $showsIssues) {
            if let environment, let repo = viewModel.gitHubRepo {
                GitHubIssuesView(repo: repo, environment: environment)
            }
        }
    }

    @ViewBuilder
    private func toolbar(viewModel: ListRowsViewModel) -> some View {
        HStack(spacing: 8) {
            // A GitHub-backed list's rows sync from GitHub issues, so the add
            // action becomes "New Issue" (opening the issue composer/browser)
            // rather than a native empty-row create, which wouldn't survive the
            // next sync. Detection is row-derived (`viewModel.isGitHubBacked`).
            if viewModel.isGitHubBacked {
                Button {
                    showsIssues = true
                } label: {
                    Label("New Issue", systemImage: "ladybug")
                }
                .help("This list syncs from GitHub — add a GitHub issue instead of a row")
            } else {
                Button {
                    Task { await viewModel.addRow() }
                } label: {
                    Label("Add Row", systemImage: "plus")
                }
            }

            Button {
                deletePending = true
            } label: {
                Label("Delete", systemImage: "minus")
            }
            .disabled(selection.isEmpty || viewModel.isGitHubBacked)

            Spacer()

            Picker("View", selection: Binding(
                get: { viewModel.viewMode },
                set: { viewModel.viewMode = $0 }
            )) {
                Label("Table", systemImage: "tablecells").tag(ListRowsViewModel.ViewMode.table)
                Label("Cards", systemImage: "rectangle.grid.2x2").tag(ListRowsViewModel.ViewMode.cards)
                Label("Schema", systemImage: "square.on.square").tag(ListRowsViewModel.ViewMode.entity)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
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

    // MARK: - Entity (schema) mode

    /// Schema-entity view (work-consolidation.md §1b): the list *is* the entity;
    /// this renders one entity box describing its schema — fields, types, `select`
    /// options, and nullability — reading the unit-tested `entityFields`
    /// projection so the view stays presentation-only.
    @ViewBuilder
    private func entityMode(viewModel: ListRowsViewModel) -> some View {
        let fields = viewModel.entityFields
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if fields.isEmpty {
                    emptySchemaState
                } else {
                    entityCard(fields: fields)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func entityCard(fields: [ListRowsViewModel.SchemaEntityField]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Entity header — the list's title names the entity.
            HStack(spacing: 8) {
                Image(systemName: "tablecells.badge.ellipsis")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(list.title)
                    .font(.ilSubtitle())
                Spacer()
                Text("\(fields.count) field\(fields.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                if index > 0 { Divider() }
                entityFieldRow(field)
            }
        }
        .background(ILColor.surface2, in: RoundedRectangle(cornerRadius: ILMetric.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: ILMetric.radiusMd)
                .strokeBorder(Color.secondary.opacity(0.2))
        )
        .frame(maxWidth: 460, alignment: .leading)
    }

    @ViewBuilder
    private func entityFieldRow(_ field: ListRowsViewModel.SchemaEntityField) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(field.name)
                .font(.ilBody().weight(.semibold))
            Spacer(minLength: 12)
            Text(field.typeDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            if let requirement = field.requirementLabel {
                Text(requirement)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entityFieldAccessibilityLabel(field))
    }

    private var emptySchemaState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.on.square")
                .font(.ilDisplay(30))
                .foregroundStyle(.secondary)
            Text("No schema defined")
                .font(.ilSubtitle())
            Text("Add typed fields in the Schema Editor to see this list's entity.")
                .font(.ilBody())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func entityFieldAccessibilityLabel(_ field: ListRowsViewModel.SchemaEntityField) -> String {
        var parts = ["\(field.name), \(field.typeDescription)"]
        if let requirement = field.requirementLabel { parts.append(requirement) }
        return parts.joined(separator: ", ")
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
