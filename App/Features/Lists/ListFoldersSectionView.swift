// ListFoldersSectionView
//
// The folder-tree section for the Lists sidebar (the-gaps.md G6). A
// self-contained section that owns its own `ListFoldersViewModel`, loads
// the tree on appear, and renders the nested folders with create /
// rename / move / delete affordances. Designed to be dropped into the
// existing `OwnedListsRootView` sidebar `List` above the lists rows so
// the change stays additive.
//
// Subscriber gate: folder creation is subscriber-only. When a create is
// blocked, the view model raises `showSubscriberUpsell`; this view
// presents a small upsell alert instead of an error, matching the
// domain's "disabled / upsell, not an error" contract.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct ListFoldersSectionView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: ListFoldersViewModel?

    // Sheet / dialog state for the mutation affordances.
    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""
    @State private var newFolderParentID: String?

    @State private var renameTarget: ListFolder?
    @State private var renameName = ""

    @State private var deleteTargetID: String?

    var body: some View {
        Section("Folders") {
            if let viewModel {
                folderList(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading folders")
                    .frame(maxWidth: .infinity)
            }
        }
        .task {
            if viewModel == nil, let environment {
                let vm = ListFoldersViewModel(service: environment.listFolders)
                viewModel = vm
                await vm.load()
            }
        }
        // New-folder name prompt. `newFolderParentID` selects the parent
        // (nil = root); "New Subfolder" context-menu items set it first.
        .alert("New folder", isPresented: $showNewFolderPrompt) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName
                let parent = newFolderParentID
                newFolderName = ""
                newFolderParentID = nil
                if let viewModel {
                    Task { await viewModel.create(name: name, parentId: parent) }
                }
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
                newFolderParentID = nil
            }
        }
        // Rename prompt.
        .alert("Rename folder", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Folder name", text: $renameName)
            Button("Rename") {
                if let target = renameTarget, let viewModel {
                    let name = renameName
                    Task { await viewModel.rename(id: target.id, to: name) }
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        // Delete confirmation.
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(
                get: { deleteTargetID != nil },
                set: { if !$0 { deleteTargetID = nil } }
            ),
            presenting: deleteTargetID
        ) { id in
            Button("Delete", role: .destructive) {
                if let viewModel { Task { await viewModel.delete(id: id) } }
                deleteTargetID = nil
            }
            Button("Cancel", role: .cancel) { deleteTargetID = nil }
        } message: { _ in
            Text("Lists inside the folder are not deleted; they return to the top level.")
        }
        // Subscriber upsell when a create is gated.
        .alert("Subscribe to use folders", isPresented: Binding(
            get: { viewModel?.showSubscriberUpsell ?? false },
            set: { if !$0 { viewModel?.dismissUpsell() } }
        )) {
            Button("OK", role: .cancel) { viewModel?.dismissUpsell() }
        } message: {
            Text("Organizing lists into folders is a subscriber feature.")
        }
    }

    // MARK: - Folder list

    @ViewBuilder
    private func folderList(viewModel: ListFoldersViewModel) -> some View {
        // "New folder at root" affordance always available.
        Button {
            newFolderParentID = nil
            showNewFolderPrompt = true
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)

        if let error = viewModel.error {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if viewModel.tree.isEmpty, viewModel.hasLoadedOnce {
            Text("No folders yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.tree) { node in
                FolderTreeRow(
                    node: node,
                    onNewSubfolder: { parentID in
                        newFolderParentID = parentID
                        showNewFolderPrompt = true
                    },
                    onRename: { folder in
                        renameName = folder.name
                        renameTarget = folder
                    },
                    onDelete: { id in deleteTargetID = id }
                )
            }
        }
    }
}

// MARK: - FolderTreeRow

/// Recursive folder row rendering a `ListFolderNode` with a disclosure
/// group when it has children. Each row carries a context menu with the
/// create-subfolder / rename / delete actions.
private struct FolderTreeRow: View {
    let node: ListFolderNode
    let onNewSubfolder: (String) -> Void
    let onRename: (ListFolder) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        Group {
            if node.children.isEmpty {
                row
            } else {
                DisclosureGroup {
                    ForEach(node.children) { child in
                        FolderTreeRow(
                            node: child,
                            onNewSubfolder: onNewSubfolder,
                            onRename: onRename,
                            onDelete: onDelete
                        )
                    }
                } label: {
                    row
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(node.name)
                .lineLimit(1)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Folder \(node.name)")
        .contextMenu {
            Button {
                onNewSubfolder(node.id)
            } label: {
                Label("New Subfolder", systemImage: "folder.badge.plus")
            }
            Button {
                onRename(node.folder)
            } label: {
                Label("Rename\u{2026}", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                onDelete(node.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
