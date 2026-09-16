// SavedViewsControl
//
// The saved-views affordance on the list rows surface (work-consolidation.md
// G40 / issue #81): a menu that applies a view, plus a manage sheet for
// create / rename / duplicate / delete / make-default.
//
// A menu and a sheet rather than a new screen: saved views arrange the rows
// pane, so the control belongs in the rows pane's own toolbar next to the
// view-mode picker. A separate screen would put the arrangement somewhere the
// user cannot see it take effect.
//
// Shared and personal views are separated into their own menu sections and
// carry distinct glyphs, because the whole point of the feature is that a
// collaborator can tell the *list's* arrangement from their own. "Duplicate"
// sits directly under the shared section — that is the spec's "escape hatch",
// and burying it would leave collaborators stuck with the owner's layout.

import SwiftUI
import InterlinedDomain

struct SavedViewsControl: View {

    let viewModel: SavedViewsViewModel
    /// `true` when the caller may read the list but not change it (a
    /// `watcher`-role share). Shared views belong to the list, so offering to
    /// create one on a list you cannot edit would be an affordance that 403s;
    /// personal views stay available because they are the caller's own.
    var isReadOnly: Bool = false

    @State private var showsManageSheet = false
    @State private var showsCreateSheet = false

    var body: some View {
        Menu {
            menuContent
        } label: {
            Label(menuTitle, systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Saved views arrange this list — shared views come from the list, personal ones are yours")
        .accessibilityLabel("Saved views")
        .sheet(isPresented: $showsCreateSheet) {
            NewSavedViewSheet(viewModel: viewModel, allowsSharedScope: !isReadOnly)
        }
        .sheet(isPresented: $showsManageSheet) {
            ManageSavedViewsSheet(viewModel: viewModel, allowsSharedScope: !isReadOnly)
        }
    }

    /// The applied view's name, or a neutral label. Not "Default" — a list
    /// with no applied view is not showing a default, it is showing the list.
    private var menuTitle: String {
        viewModel.selectedView?.name ?? "All Records"
    }

    @ViewBuilder
    private var menuContent: some View {
        Button {
            viewModel.select(viewID: nil)
        } label: {
            Label("All Records", systemImage: viewModel.selectedViewID == nil ? "checkmark" : "list.bullet")
        }

        if !viewModel.sharedViews.isEmpty {
            Section("Shared with the list") {
                ForEach(viewModel.sharedViews) { view in
                    viewButton(view, systemImage: "person.2")
                }
            }
        }

        if !viewModel.personalViews.isEmpty {
            Section("My views") {
                ForEach(viewModel.personalViews) { view in
                    viewButton(view, systemImage: "person")
                }
            }
        }

        Divider()

        Button("Save Current Arrangement\u{2026}") {
            showsCreateSheet = true
        }

        // The escape hatch, surfaced at the top level rather than only inside
        // the manage sheet: taking a copy of someone's shared view is the
        // action a collaborator reaches for most.
        if let selected = viewModel.selectedView {
            Button("Duplicate \u{201C}\(selected.name)\u{201D}") {
                Task { await viewModel.fork(viewID: selected.id, name: "\(selected.name) copy") }
            }
        }

        Button("Manage Views\u{2026}") {
            showsManageSheet = true
        }
    }

    @ViewBuilder
    private func viewButton(_ view: SavedListView, systemImage: String) -> some View {
        Button {
            viewModel.select(viewID: view.id)
        } label: {
            Label(
                view.isDefault ? "\(view.name) (default)" : view.name,
                systemImage: viewModel.selectedViewID == view.id ? "checkmark" : systemImage
            )
        }
    }
}

// MARK: - Create sheet

/// Names a new view and picks its scope. Scope is a deliberate, explicit
/// choice rather than a default: `shared` publishes the arrangement to everyone
/// with access to the list, and that is not something to fall into.
private struct NewSavedViewSheet: View {

    let viewModel: SavedViewsViewModel
    let allowsSharedScope: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var scope: SavedListViewScope = .personal
    @State private var makeDefault: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Current Arrangement")
                .font(.ilSubtitle())

            TextField("View name", text: $name)
                .textFieldStyle(.roundedBorder)

            if allowsSharedScope {
                Picker("Visible to", selection: $scope) {
                    Text("Only me").tag(SavedListViewScope.personal)
                    Text("Everyone on this list").tag(SavedListViewScope.shared)
                }
                .pickerStyle(.radioGroup)
            } else {
                // Read-only share: a shared view belongs to the list, so
                // offering it here would be an affordance the server refuses.
                Label("Saved to your own views", systemImage: "person")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }

            Toggle("Open this list with this view", isOn: $makeDefault)
                .help("Defaults are per person — yours does not change what collaborators see")

            if let message = viewModel.validationMessage {
                Text(message)
                    .font(.ilMono(10))
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    Task {
                        await viewModel.create(
                            name: name,
                            scope: allowsSharedScope ? scope : .personal,
                            makeDefault: makeDefault
                        )
                        if viewModel.validationMessage == nil, viewModel.error == nil {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 380)
    }
}

// MARK: - Manage sheet

/// Lists every view grouped by scope and offers rename / duplicate / delete /
/// make-default per row.
private struct ManageSavedViewsSheet: View {

    let viewModel: SavedViewsViewModel
    let allowsSharedScope: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var renamingViewID: String?
    @State private var renameText: String = ""
    @State private var deletePendingViewID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved Views")
                    .font(.ilSubtitle())
                Spacer()
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(16)

            Divider()

            if viewModel.views.isEmpty {
                emptyState
            } else {
                List {
                    if !viewModel.sharedViews.isEmpty {
                        Section("Shared with the list") {
                            ForEach(viewModel.sharedViews) { row($0) }
                        }
                    }
                    if !viewModel.personalViews.isEmpty {
                        Section("My views") {
                            ForEach(viewModel.personalViews) { row($0) }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if let error = viewModel.error {
                Divider()
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.ilMono(10))
                    .padding(8)
            }
            if let message = viewModel.validationMessage {
                Divider()
                Text(message)
                    .font(.ilMono(10))
                    .foregroundStyle(.red)
                    .padding(8)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 460, minHeight: 320)
        .confirmationDialog(
            "Delete this view?",
            isPresented: Binding(
                get: { deletePendingViewID != nil },
                set: { if !$0 { deletePendingViewID = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let id = deletePendingViewID {
                    Task { await viewModel.delete(viewID: id) }
                }
                deletePendingViewID = nil
            }
            Button("Cancel", role: .cancel) { deletePendingViewID = nil }
        } message: {
            Text("Deleting a shared view removes it for everyone on this list.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.ilDisplay(32))
                .foregroundStyle(.secondary)
            Text("No saved views")
                .font(.ilSubtitle())
            Text("Save the current arrangement to come back to it later.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    @ViewBuilder
    private func row(_ view: SavedListView) -> some View {
        HStack(spacing: 8) {
            Image(systemName: view.isShared ? "person.2" : "person")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if renamingViewID == view.id {
                TextField("View name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(view) }
                Button("Save") { commitRename(view) }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { renamingViewID = nil }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(view.name)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(view.scope.displayName)
                        Text("· \(view.config.density.displayName)")
                        if view.isDefault {
                            Text("· opens by default")
                        }
                    }
                    .font(.ilMono(9))
                    .foregroundStyle(.secondary)
                }
                Spacer()

                if viewModel.pendingOperations.contains(view.id) {
                    ProgressView().controlSize(.small)
                }

                // Duplicate is offered on every row, shared or personal: the
                // live API forks a personal view too, and "make me a copy I can
                // change" is the same intent either way.
                Button {
                    Task { await viewModel.fork(viewID: view.id, name: "\(view.name) copy") }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .help("Duplicate into your own views")

                if !view.isDefault {
                    Button {
                        Task { await viewModel.makeDefault(viewID: view.id) }
                    } label: {
                        Image(systemName: "star")
                    }
                    .buttonStyle(.borderless)
                    .help("Open this list with this view")
                }

                // Renaming and deleting a shared view changes it for everyone,
                // so on a read-only share those are hidden rather than shown
                // disabled (the project's "never enabled-but-broken" rule).
                if !view.isShared || allowsSharedScope {
                    Button {
                        renameText = view.name
                        renamingViewID = view.id
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Rename")

                    Button(role: .destructive) {
                        deletePendingViewID = view.id
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func commitRename(_ view: SavedListView) {
        let name = renameText
        renamingViewID = nil
        Task { await viewModel.rename(viewID: view.id, to: name) }
    }
}
