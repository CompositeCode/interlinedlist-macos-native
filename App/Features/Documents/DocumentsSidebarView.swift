// DocumentsSidebarView
//
// Sidebar (leftmost column) of the M4 Documents three-column split
// (PLAN.md §6 M4). Folder tree with disclosure groups, per-folder
// context menu for rename / delete / new sub-folder, and a
// "Documents" root row that means "show unfiled documents."
// Pure SwiftUI; no AppKit involvement.

import SwiftUI
import InterlinedDomain

struct DocumentsSidebarView: View {

    let viewModel: FolderTreeViewModel
    let onSelect: (FolderNode.ID?) -> Void

    @State private var pendingRenameID: FolderNode.ID?
    @State private var renameDraft: String = ""
    @State private var pendingDeleteID: FolderNode.ID?
    @State private var pendingNewSubfolderParentID: FolderNode.ID?
    @State private var subfolderDraft: String = ""
    @State private var showNewRootFolder: Bool = false

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedFolderID },
            set: { id in
                viewModel.select(id: id)
                onSelect(id)
            }
        )) {
            // Unfiled root — selecting it shows documents with no folder.
            Label("All Documents", systemImage: "tray")
                .tag(FolderNode.ID?.none)

            if viewModel.folders.isEmpty, viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                let tree = viewModel.tree
                ForEach(tree.roots) { folder in
                    FolderSidebarRow(
                        folder: folder,
                        tree: tree,
                        onRenameRequested: { id, current in
                            pendingRenameID = id
                            renameDraft = current
                        },
                        onDeleteRequested: { pendingDeleteID = $0 },
                        onAddSubfolderRequested: { id in
                            pendingNewSubfolderParentID = id
                            subfolderDraft = ""
                        }
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .toolbar {
            ToolbarItem {
                Button {
                    showNewRootFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .help("Create a new top-level folder")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .alert("New folder", isPresented: $showNewRootFolder) {
            TextField("Folder name", text: $subfolderDraft)
            Button("Create") {
                Task {
                    let name = subfolderDraft
                    subfolderDraft = ""
                    _ = await viewModel.createFolder(name: name, parentId: nil)
                }
            }
            Button("Cancel", role: .cancel) {
                subfolderDraft = ""
            }
        }
        .alert(
            "New sub-folder",
            isPresented: Binding(
                get: { pendingNewSubfolderParentID != nil },
                set: { if !$0 { pendingNewSubfolderParentID = nil } }
            )
        ) {
            TextField("Folder name", text: $subfolderDraft)
            Button("Create") {
                Task {
                    let parent = pendingNewSubfolderParentID
                    let name = subfolderDraft
                    pendingNewSubfolderParentID = nil
                    subfolderDraft = ""
                    _ = await viewModel.createFolder(name: name, parentId: parent)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingNewSubfolderParentID = nil
                subfolderDraft = ""
            }
        }
        .alert(
            "Rename folder",
            isPresented: Binding(
                get: { pendingRenameID != nil },
                set: { if !$0 { pendingRenameID = nil } }
            )
        ) {
            TextField("New name", text: $renameDraft)
            Button("Rename") {
                Task {
                    if let id = pendingRenameID {
                        await viewModel.renameFolder(id: id, to: renameDraft)
                    }
                    pendingRenameID = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRenameID = nil
            }
        }
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            presenting: pendingDeleteID
        ) { id in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteFolder(id: id)
                    pendingDeleteID = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteID = nil
            }
        } message: { _ in
            Text("Deleting a folder also removes the documents inside it.")
        }
    }
}

// MARK: - Recursive sidebar row

private struct FolderSidebarRow: View {

    let folder: FolderNode
    let tree: FolderTree
    let onRenameRequested: (FolderNode.ID, String) -> Void
    let onDeleteRequested: (FolderNode.ID) -> Void
    let onAddSubfolderRequested: (FolderNode.ID) -> Void

    var body: some View {
        let children = tree.children(of: folder.id)
        Group {
            if children.isEmpty {
                row
            } else {
                DisclosureGroup {
                    ForEach(children) { child in
                        FolderSidebarRow(
                            folder: child,
                            tree: tree,
                            onRenameRequested: onRenameRequested,
                            onDeleteRequested: onDeleteRequested,
                            onAddSubfolderRequested: onAddSubfolderRequested
                        )
                    }
                } label: {
                    row
                }
            }
        }
        .tag(Optional.some(folder.id))
    }

    private var row: some View {
        Label(folder.name, systemImage: "folder")
            .contextMenu {
                Button {
                    onAddSubfolderRequested(folder.id)
                } label: {
                    Label("New Sub-folder", systemImage: "folder.badge.plus")
                }
                Button {
                    onRenameRequested(folder.id, folder.name)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    onDeleteRequested(folder.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}
