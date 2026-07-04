// DocumentsListView
//
// Middle column of the M4 Documents three-column split
// (PLAN.md §6 M4). Lists documents in the currently-selected folder
// (or the unfiled root) with a per-row context menu for delete.
// Pure SwiftUI; no AppKit involvement.

import SwiftUI
import InterlinedDomain

struct DocumentsListView: View {

    let viewModel: DocumentsListViewModel
    let onSelect: (Document.ID?) -> Void

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
                    .frame(maxWidth: .infinity)
            } else if viewModel.documentsLoaded.isEmpty {
                Text("No documents yet — create one to begin.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.documentsLoaded) { doc in
                    DocumentRowView(document: doc)
                        .tag(doc.id)
                        .contextMenu {
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
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
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
    }
}
