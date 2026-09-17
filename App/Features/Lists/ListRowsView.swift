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
    /// `true` when the signed-in account may read this list but not change it —
    /// a `watcher`-role share (work-consolidation.md G23). Row-mutating
    /// affordances are *hidden*, not disabled, per the project's
    /// "never enabled-but-broken" rule. Defaults to `false` so every existing
    /// owned-list call site is unchanged.
    var isReadOnly: Bool = false

    @Environment(\.appEnvironment) private var environment
    @State private var selection: Set<String> = []
    /// Presents the Add Row form.
    @State private var showsAddRow = false

    @State private var deletePending: Bool = false
    /// Presents the GitHub issue browser/composer for a GitHub-backed list —
    /// the row-creation route for lists whose rows sync from GitHub.
    @State private var showsIssues: Bool = false

    /// Drives the "Create from…" sheet for the selected rows
    /// (work-consolidation.md G16).
    @State private var showsCreateFrom = false

    /// Drives the saved-views menu (work-consolidation.md G40). Built here
    /// rather than by the parent so the control ships with the rows pane it
    /// arranges — and so a list opened from the "Shared with me" section gets
    /// one too, which is the case the feature exists for.
    @State private var savedViewsViewModel: SavedViewsViewModel?

    var body: some View {
        content(viewModel: viewModel)
            .navigationTitle(list.title)
            .task(id: viewModel.listId) {
                guard let environment else { return }
                let model = SavedViewsViewModel(
                    lists: environment.lists,
                    eventBus: environment.listsEventBus,
                    listId: viewModel.listId
                )
                savedViewsViewModel = model
                // `load()` applies the caller's `isDefault` view, so the list
                // opens in the arrangement that person chose — which on a
                // shared list is not the same as the one the owner chose.
                await model.load()
                await subscribeSavedViews(model: model, bus: environment.listsEventBus)
            }
    }

    /// Cross-window sync for saved-view writes. `[weak model]` per the project
    /// rule: Swift 6 Observation does not guarantee `deinit`-time cancellation,
    /// so the subscriber must not keep the view model alive by itself.
    private func subscribeSavedViews(model: SavedViewsViewModel, bus: ListsEventBus) async {
        Task { [weak model] in
            for await event in bus.events() {
                guard let model else { return }
                model.apply(event: event)
            }
        }
    }

    /// How many lines a table / card cell renders. The one `config` value a
    /// saved view stores that has a visible effect in this client: the server
    /// normalises `mode` to `records` and drops every column/sort key, so
    /// `density` is the whole of "applying a view" today (issue #81).
    private var cellLineLimit: Int {
        savedViewsViewModel?.appliedDensity == .compact ? 1 : 2
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
        .sheet(isPresented: $showsAddRow) {
            AddRowSheetView(
                listId: list.id,
                schema: viewModel.schema,
                onSaved: { Task { await viewModel.initialLoad() } }
            )
        }
        .sheet(isPresented: $showsIssues) {
            if let environment, let repo = viewModel.gitHubRepo {
                GitHubIssuesView(repo: repo, environment: environment)
            }
        }
        .sheet(isPresented: $showsCreateFrom) {
            if let environment {
                CreateFromSheet(
                    source: .rows(listId: list.id, rowIds: Array(selection)),
                    environment: environment
                )
            }
        }
    }

    /// The repository a GitHub-backed list came from, linked, with a warning tag
    /// when it is private (GitHub #50).
    ///
    /// `githubRepoPrivate` has been on the wire since the list routes shipped
    /// and the client never read it. The tag is not decoration: a link to a
    /// private repository sends a visitor to a GitHub sign-in or a "not found"
    /// page, and the help page is explicit that the list should say so before
    /// they follow it.
    ///
    /// Absent — rather than shown as "public" — when the server did not say.
    @ViewBuilder
    private var gitHubRepositoryBadge: some View {
        if let source = list.gitHubSource, let repository = source.repository {
            HStack(spacing: 4) {
                if let url = source.repositoryURL {
                    Link(destination: url) {
                        Label("\(repository) issues", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.ilMono(10))
                    }
                    .help("Open \(repository) on GitHub")
                } else {
                    Label(repository, systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
                if source.isRepositoryPrivate == true {
                    Text("Private repo")
                        .font(.ilMono(9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(ILColor.surface2, in: Capsule())
                        .foregroundStyle(.secondary)
                        .help("This repository is private — anyone without access will see a sign-in or a “not found” page")
                }
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
            if isReadOnly {
                Label("Read-only", systemImage: "eye")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .help("This list was shared with you for viewing — you can't change its rows")
            } else if viewModel.isGitHubBacked {
                Button {
                    showsIssues = true
                } label: {
                    Label("New Issue", systemImage: "ladybug")
                }
                .help("This list syncs from GitHub — add a GitHub issue instead of a row")
                gitHubRepositoryBadge
            } else {
                Button {
                    // The form, not a blank row (GitHub #50). `addRow()` created
                    // an empty row and left the user to fill it in through the
                    // inspector — which is why the columns' help text,
                    // placeholders and validation rules had nowhere to appear.
                    showsAddRow = true
                } label: {
                    Label("Add Row", systemImage: "plus")
                }
                .disabled(viewModel.schema.fields.isEmpty)
                .help(
                    viewModel.schema.fields.isEmpty
                        ? "Add columns in Edit Schema before adding rows"
                        : "Add a row"
                )
            }

            if !isReadOnly {
                Button {
                    deletePending = true
                } label: {
                    Label("Delete", systemImage: "minus")
                }
                .disabled(selection.isEmpty || viewModel.isGitHubBacked)
            }

            // "Create from…" over the current row selection
            // (work-consolidation.md G16). Unlike Delete this is safe on a
            // GitHub-backed list: it reads the rows, it does not write them.
            Button {
                showsCreateFrom = true
            } label: {
                Label("Create from\u{2026}", systemImage: "plus.rectangle.on.folder")
            }
            .disabled(selection.isEmpty)
            .help("Turn the selected rows into a new list or document")

            // Saved views sit next to the view-mode picker because both
            // change how these rows are arranged — one per session, one saved
            // and shareable (work-consolidation.md G40).
            if let savedViewsViewModel {
                SavedViewsControl(viewModel: savedViewsViewModel, isReadOnly: isReadOnly)
            }

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
                TableColumnForEach(columns) { column in
                    // Header from `label`, cell lookup by `key` — see `ListColumn`
                    // (#50) — at the row height the active saved view asks for
                    // (G40). Both landed on this line; they compose, and taking
                    // either alone loses something real: dropping `ListColumn`
                    // reintroduces the empty-cell bug for a column whose key
                    // differs from its label, and dropping `cellLineLimit`
                    // silently ignores the view's density.
                    TableColumn(column.label) { (row: ListRow) in
                        Text(row.fields[column.key]?.displayText ?? "")
                            .lineLimit(cellLineLimit)
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
    private func effectiveColumns(_ viewModel: ListRowsViewModel) -> [ListColumn] {
        if !viewModel.columns.isEmpty { return viewModel.columns }
        var seen = Set<String>()
        var ordered: [ListColumn] = []
        for row in viewModel.rows {
            for key in row.fields.keys.sorted() where !seen.contains(key) {
                seen.insert(key)
                // No schema means no separate label; the key is the header.
                ordered.append(ListColumn(key: key, label: key))
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
    private func rowCard(row: ListRow, columns: [ListColumn]) -> some View {
        let keys = columns.isEmpty
            ? row.fields.keys.sorted().map { ListColumn(key: $0, label: $0) }
            : columns
        VStack(alignment: .leading, spacing: 4) {
            ForEach(keys) { column in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(column.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(row.fields[column.key]?.displayText ?? "")
                        .font(.ilBody())
                        .lineLimit(cellLineLimit)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(ILColor.surface2, in: RoundedRectangle(cornerRadius: ILMetric.radiusMd))
    }

    private func rowAccessibilityLabel(row: ListRow, columns: [ListColumn]) -> String {
        let keys = columns.isEmpty
            ? row.fields.keys.sorted().map { ListColumn(key: $0, label: $0) }
            : columns
        let pairs = keys.compactMap { column -> String? in
            guard let value = row.fields[column.key]?.displayText, !value.isEmpty else { return nil }
            return "\(column.label): \(value)"
        }
        return pairs.isEmpty ? "Row" : pairs.joined(separator: ", ")
    }

    private func shouldLoadMore(_ row: ListRow, in loaded: [ListRow]) -> Bool {
        guard let index = loaded.firstIndex(where: { $0.id == row.id }) else { return false }
        return index >= max(0, loaded.count - 5)
    }

}
