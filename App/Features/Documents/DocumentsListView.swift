// DocumentsListView
//
// Middle column of the M4 Documents three-column split
// (PLAN.md §6 M4). Lists documents in the currently-selected folder
// (or the unfiled root) with a per-row context menu for move + delete
// (work-consolidation.md G24 adds the move half).
// Pure SwiftUI; no AppKit involvement.

import SwiftUI
import InterlinedDomain

struct DocumentsListView: View {

    let viewModel: DocumentsListViewModel
    let onSelect: (Document.ID?) -> Void

    /// Source of the **Move to folder** destinations. Optional so the column
    /// still renders in isolation (previews, and any future host that has no
    /// sidebar); the move item is simply absent without it.
    var folderTree: FolderTreeViewModel? = nil

    /// Called with the document that was moved, so the host can rebind an open
    /// editor to the server's relocated copy.
    var onMoved: ((Document) -> Void)? = nil

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedDocumentID },
            set: { id in
                viewModel.select(id: id)
                onSelect(id)
            }
        )) {
            if viewModel.documentsLoaded.isEmpty, viewModel.isLoading {
                ProgressView()
                    .accessibilityLabel("Loading documents")
                    .frame(maxWidth: .infinity)
            } else if viewModel.documentsLoaded.isEmpty, let error = viewModel.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Could not load documents")
                        .font(.ilBody())
                    Text(error.localizedDescription)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .frame(maxWidth: .infinity)
            } else if viewModel.documentsLoaded.isEmpty {
                Text("No documents yet — create one to begin.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.documentsLoaded) { doc in
                    DocumentRowView(document: doc)
                        .tag(doc.id)
                        .contextMenu {
                            if let folderTree {
                                MoveToFolderMenu(
                                    folderTree: folderTree,
                                    currentFolderID: doc.folderId
                                ) { destination in
                                    Task {
                                        if let moved = await viewModel.moveDocument(
                                            id: doc.id,
                                            to: destination
                                        ) {
                                            onMoved?(moved)
                                            // The sidebar's per-folder counts
                                            // came from the tree call, so both
                                            // the source and destination badges
                                            // are now stale.
                                            await folderTree.refresh()
                                        }
                                    }
                                }
                                Divider()
                            }
                            Button(role: .destructive) {
                                Task { await viewModel.deleteDocument(id: doc.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color(.controlBackgroundColor))
        .refreshable {
            await viewModel.refresh()
        }
    }
}

// MARK: - DocumentRowView

private struct DocumentRowView: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(document.title.isEmpty ? "Untitled" : document.title)
                .font(.ilBody())
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                if document.isPublic {
                    Image(systemName: "globe")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Public document")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(documentAccessibilityLabel)
    }

    private var documentAccessibilityLabel: String {
        let title = document.title.isEmpty ? "Untitled" : document.title
        let date = document.updatedAt.formatted(date: .abbreviated, time: .shortened)
        let visibility = document.isPublic ? ", public document" : ""
        return "\(title), updated \(date)\(visibility)"
    }
}
