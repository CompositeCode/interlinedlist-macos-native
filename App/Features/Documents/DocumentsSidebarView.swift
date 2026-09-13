// DocumentsSidebarView
//
// Sidebar (leftmost column) of the M4 Documents three-column split
// (PLAN.md §6 M4). Folder tree with disclosure groups, per-folder
// context menu for rename / delete / new sub-folder, and a
// "Documents" root row that means "show unfiled documents."
// Pure SwiftUI; no AppKit involvement.
//
// work-consolidation.md G24: the whole thing is painted from one call.
// `FolderTreeViewModel` now reads `GET /api/documents/tree`, which carries
// each folder's documents inline — so the per-folder counts rendered here
// cost nothing extra. A count is shown only once the tree has actually
// landed (`documentCount(for:)` returns `nil` while the view is painting
// from cache), so a cached row never displays an authoritative-looking
// zero it hasn't earned.

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
            HStack {
                Label("All Documents", systemImage: "tray")
                Spacer()
                FolderCountBadge(count: viewModel.documentCount(for: nil))
            }
            .tag(FolderNode.ID?.none)

            if viewModel.folders.isEmpty, viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.folders.isEmpty, let error = viewModel.error {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Folders unavailable")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                    Text(error.localizedDescription)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            } else {
                let tree = viewModel.tree
                ForEach(tree.roots) { folder in
                    FolderSidebarRow(
                        folder: folder,
                        tree: tree,
                        documentCount: { viewModel.documentCount(for: $0) },
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
    /// How many documents are filed directly in a folder, or `nil` when the
    /// tree hasn't landed yet. Passed as a closure so the recursive row does
    /// not need the whole view model.
    let documentCount: (FolderNode.ID) -> Int?
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
                            documentCount: documentCount,
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
        HStack {
            Label(folder.name, systemImage: "folder")
            Spacer()
            // Direct children only — the tree nests documents under the folder
            // that holds them, so a parent does not roll up its sub-folders.
            FolderCountBadge(count: documentCount(folder.id))
        }
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

// MARK: - Folder count badge

/// Trailing document count for a sidebar row.
///
/// Renders nothing at all for `nil` (the tree hasn't landed) *and* for zero —
/// an empty folder reads better as a folder with no badge than as one
/// annotated "0". The distinction still matters upstream: `nil` means unknown,
/// so nothing is claimed about a folder we haven't fetched.
private struct FolderCountBadge: View {

    let count: Int?

    var body: some View {
        if let count, count > 0 {
            Text("\(count)")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(count) documents")
        }
    }
}
