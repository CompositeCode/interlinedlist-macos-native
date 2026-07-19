// DocumentsRootView
//
// The M4 Documents root (PLAN.md §6 M4). A three-column
// `NavigationSplitView`:
//   - Sidebar  — `DocumentsSidebarView` (folder tree + "All Documents").
//   - Content  — `DocumentsListView` (documents in selected folder).
//   - Detail   — `DocumentEditorView` (Markdown editor + Textual preview).
//
// Also owns:
//   - The toolbar (New Document, Sync Now, sync-status indicator).
//   - The on-launch + manual sync trigger.
//   - The subscription to `documentSyncEvents` — routes
//     `deltaApplied` into the list view model and `conflictResolved`
//     into the editor view model (when the conflict's original id
//     matches the currently-open document).
//
// Pure SwiftUI; no AppKit involvement. Decision 0003 compliance: this
// file consumes only `InterlinedDomain` (no `InterlinedKit` import).

import SwiftUI
import InterlinedDomain

struct DocumentsRootView: View {

    /// Pre-warmed view models supplied by `MainWindowView`. When non-nil
    /// the view skips creation and their individual initial loads; the
    /// editor and sync-status are always created fresh here since they
    /// have no network cost at init time.
    var preloadedFolderTree: FolderTreeViewModel? = nil
    var preloadedDocumentsList: DocumentsListViewModel? = nil

    @Environment(\.appEnvironment) private var environment
    @State private var folderTree: FolderTreeViewModel?
    @State private var documentsList: DocumentsListViewModel?
    @State private var editor: DocumentEditorViewModel?
    @State private var syncStatus: SyncStatusViewModel?

    /// Drives the "New from Template…" picker sheet (feature-gaps.md §1.4).
    @State private var isTemplatePickerPresented = false

    var body: some View {
        Group {
            if let environment, let folderTree, let documentsList, let editor, let syncStatus {
                content(
                    environment: environment,
                    folderTree: folderTree,
                    documentsList: documentsList,
                    editor: editor,
                    syncStatus: syncStatus
                )
            } else {
                unconfiguredState
            }
        }
        .task {
            await initializeIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentsNewDocument)) { _ in
            Task { await handleNewDocument() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentsNewFromTemplate)) { _ in
            isTemplatePickerPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentsSyncNow)) { _ in
            Task { await syncStatus?.syncNow() }
        }
        .sheet(isPresented: $isTemplatePickerPresented) {
            if let documentsList {
                DocumentTemplatePickerView(viewModel: documentsList) { created in
                    editor?.bind(to: created)
                }
            }
        }
    }

    @ViewBuilder
    private func content(
        environment: AppEnvironment,
        folderTree: FolderTreeViewModel,
        documentsList: DocumentsListViewModel,
        editor: DocumentEditorViewModel,
        syncStatus: SyncStatusViewModel
    ) -> some View {
        NavigationSplitView {
            DocumentsSidebarView(viewModel: folderTree) { folderID in
                Task {
                    await documentsList.reload(in: folderID)
                    editor.bind(to: documentsList.selectedDocument)
                }
            }
        } content: {
            DocumentsListView(viewModel: documentsList) { docID in
                let document = documentsList.documentsLoaded.first { $0.id == docID }
                editor.bind(to: document)
            }
        } detail: {
            if editor.document != nil {
                DocumentEditorView(viewModel: editor) { localCopyID in
                    handleOpenLocalCopy(
                        localCopyID,
                        documentsList: documentsList,
                        editor: editor
                    )
                }
            } else {
                placeholderEditor
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await handleNewDocument() }
                } label: {
                    Label("New Document", systemImage: "doc.badge.plus")
                }
                .keyboardShortcut("n", modifiers: [.option, .command])
                .help("Create a new document in this folder")

                Button {
                    isTemplatePickerPresented = true
                } label: {
                    Label("New from Template", systemImage: "doc.badge.gearshape")
                }
                .keyboardShortcut("n", modifiers: [.option, .command, .shift])
                .help("Create a new document from a starter template")

                Button {
                    Task { await syncStatus.syncNow() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(syncStatus.isSyncing)
                .help("Pull remote changes and push local edits")

                SyncStatusView(viewModel: syncStatus)
            }
        }
    }

    // MARK: - Setup

    private func initializeIfNeeded() async {
        guard folderTree == nil, let environment else { return }
        let tree = preloadedFolderTree ?? FolderTreeViewModel(documents: environment.documentsService)
        let list = preloadedDocumentsList ?? DocumentsListViewModel(documents: environment.documentsService)
        let edit = DocumentEditorViewModel(documents: environment.documentsService)
        let status = SyncStatusViewModel(documents: environment.documentsService)
        self.folderTree = tree
        self.documentsList = list
        self.editor = edit
        self.syncStatus = status
        // Skip initial loads for pre-warmed VMs — their loads were already
        // kicked off by MainWindowView on launch.
        if preloadedFolderTree == nil { await tree.initialLoad() }
        if preloadedDocumentsList == nil { await list.reload(in: nil) }
        await subscribeToSyncEvents(
            documentTree: tree,
            list: list,
            editor: edit,
            status: status,
            stream: environment.documentSyncEvents
        )
    }

    private func subscribeToSyncEvents(
        documentTree: FolderTreeViewModel,
        list: DocumentsListViewModel,
        editor: DocumentEditorViewModel,
        status: SyncStatusViewModel,
        stream: AsyncStream<DocumentSyncEvent>
    ) async {
        // Spawn a long-lived task; the `[weak]` captures match the
        // Wave 3 cross-window-bus pattern so a deallocated view tree
        // doesn't keep the loop alive.
        Task { [weak documentTree, weak list, weak editor, weak status] in
            for await event in stream {
                guard let documentTree, let list, let editor, let status else { return }
                switch event {
                case .deltaApplied:
                    await list.apply(event: event)
                    // Folders may have changed too — request a fresh
                    // tree; cheap and keeps the sidebar honest.
                    await documentTree.refresh()
                    // Successful application implies a successful sync
                    // cycle; reflect that in the status indicator so
                    // the on-launch auto-sync also moves the badge.
                    status.recordExternalSyncSuccess(at: Date())
                case .conflictResolved(let original, let preservedAs):
                    if editor.document?.id == original {
                        let title = list.documentsLoaded.first { $0.id == preservedAs }?.title
                            ?? editor.document?.title
                            ?? "this document"
                        editor.recordConflict(preservedAs: preservedAs, title: title)
                    }
                case .pushed:
                    // The editor pane drops its "saving" chrome on its
                    // own (the save round-trip completes there). No
                    // list mutation needed.
                    break
                }
            }
        }
    }

    // MARK: - Intents

    private func handleNewDocument() async {
        guard let documentsList else { return }
        // Auto-title: "Untitled" — the user immediately gets a buffer
        // with the title field focused so they can rename it.
        if let created = await documentsList.createDocument(title: "Untitled") {
            editor?.bind(to: created)
        }
    }

    private func handleOpenLocalCopy(
        _ id: Document.ID,
        documentsList: DocumentsListViewModel,
        editor: DocumentEditorViewModel
    ) {
        // The local copy may not yet be in the rendered list (the
        // delta apply has finished but the user might be on a
        // different folder). Refresh the current folder; if the local
        // copy is visible after that, select it.
        Task {
            await documentsList.refresh()
            if let copy = documentsList.documentsLoaded.first(where: { $0.id == id }) {
                documentsList.select(id: id)
                editor.bind(to: copy)
            }
        }
        editor.dismissConflict()
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Documents unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderEditor: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Select a document")
                .font(.ilSubtitle())
            Text("Pick a document from the list, or create a new one.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
