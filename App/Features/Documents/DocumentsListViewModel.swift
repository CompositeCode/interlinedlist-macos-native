// DocumentsListViewModel
//
// Drives the M4 Documents content list (PLAN.md §6 M4 — middle column of
// the three-column `NavigationSplitView`). Owns the loaded documents for
// the currently-selected folder, the document selection, paging, and the
// loading / error state. Reads through `DocumentsServicing` only.
//
// The owning view holds one `DocumentsListViewModel` and rebuilds it
// (`reload(in:)`) when the user picks a different folder in the
// sidebar. The view model also exposes `apply(event:)` so the documents
// event loop can fold `DocumentSyncEvent`s into the rendered list
// without a refetch (the App-layer pattern proven in Wave 4.3).
//
// Decision 0003 compliance: this file consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class DocumentsListViewModel {

    /// Page size for the documents-in-folder fetch. Matches the other
    /// view models so the App layer's paging defaults are uniform.
    static let pageSize: Int = 100

    private let documents: DocumentsServicing

    // MARK: - Observable state

    /// The folder whose documents are loaded (or `nil` for unfiled).
    private(set) var folderID: FolderNode.ID?

    /// Documents loaded so far, ordered most-recently-updated first.
    private(set) var documentsLoaded: [Document] = []

    /// Currently selected document id, if any. Drives the detail
    /// (editor + preview) pane.
    var selectedDocumentID: Document.ID?

    /// True while a documents round-trip is in flight (initial, refresh,
    /// load-more, or per-document CRUD).
    private(set) var isLoading: Bool = false

    /// True while a background revalidation runs *after* the cache has
    /// already painted the list (stale-while-revalidate, PLAN.md §5).
    private(set) var isRefreshing: Bool = false

    /// True when a background revalidation failed while cached documents
    /// were on screen. The list keeps its cached rows; the view surfaces
    /// this as an unobtrusive hint rather than blanking the column.
    private(set) var refreshFailed: Bool = false

    /// Surfaced error from the most recent failed load / create /
    /// delete. Cleared on the next successful round-trip.
    private(set) var error: Error?

    /// Timestamp of the last successful network refresh — drives the TTL.
    private(set) var lastRefreshedAt: Date?

    /// Freshness window: a re-appearing view whose documents refreshed
    /// within this many seconds skips revalidation and trusts cache.
    static let refreshTTL: TimeInterval = 45

    /// Whether a `.task`-driven re-appearance should revalidate.
    var shouldRefresh: Bool {
        guard let lastRefreshedAt else { return true }
        return Date().timeIntervalSince(lastRefreshedAt) >= Self.refreshTTL
    }

    /// Whether the server reports more pages beyond what's loaded.
    private(set) var hasMore: Bool = false

    /// The `offset` to pass on the next `loadMore` call. `nil` when
    /// `hasMore` is false.
    private(set) var nextOffset: Int?

    /// Currently selected document, if any. Computed lazily so the
    /// detail pane can render against the freshest copy.
    var selectedDocument: Document? {
        guard let selectedDocumentID else { return nil }
        return documentsLoaded.first { $0.id == selectedDocumentID }
    }

    // MARK: - Init

    init(documents: DocumentsServicing) {
        self.documents = documents
    }

    // MARK: - Intents

    /// Reloads the list for `folderID`, stale-while-revalidate (PLAN.md §5):
    /// paint the folder's cached documents immediately (no blocking spinner
    /// when non-empty), then revalidate over the network in the background.
    /// A cold folder (empty cache) keeps the blocking-spinner behavior.
    /// Resets paging + selection. Safe to call repeatedly; the sidebar
    /// selection-change handler calls it every time the user picks a folder.
    func reload(in folderID: FolderNode.ID?) async {
        self.folderID = folderID
        selectedDocumentID = nil
        hasMore = false
        nextOffset = nil
        let cached = await documents.cachedDocuments(in: folderID)
        let paintedFromCache = !cached.isEmpty
        documentsLoaded = cached  // empty for a cold folder → spinner shows
        await revalidate(cachePainted: paintedFromCache)
    }

    /// Refreshes the rendered list. Triggered by the toolbar refresh
    /// button and by the documents event loop after a `deltaApplied`
    /// event for the current folder. Always bypasses the TTL.
    func refresh() async {
        await revalidate(cachePainted: !documentsLoaded.isEmpty)
    }

    /// Appends the next page when one exists. No-op while a load is
    /// in flight or when `hasMore` is false.
    func loadMore() async {
        guard !isLoading, hasMore, let offset = nextOffset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await documents.documents(
                in: folderID,
                limit: Self.pageSize,
                offset: offset
            )
            documentsLoaded.append(contentsOf: page)
            // The domain service returns a plain `[Document]`, so the
            // "has more" heuristic is "we got a full page" (the kit
            // hides the wire-level `hasMore` boolean for paged lists).
            hasMore = page.count == Self.pageSize
            nextOffset = hasMore ? offset + page.count : nil
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Selects a document by id (or `nil` for "no selection").
    func select(id: Document.ID?) {
        selectedDocumentID = id
    }

    /// Creates a new document in the current folder. On success
    /// prepends to the rendered list and selects it. Refuses empty
    /// titles up front so the service stays focused on transport-level
    /// concerns.
    @discardableResult
    func createDocument(title: String, body: String = "", isPublic: Bool = false) async -> Document? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            error = DocumentsUIError.invalidDocumentTitle
            return nil
        }
        do {
            let doc = try await documents.create(
                title: trimmedTitle,
                body: body,
                folderId: folderID,
                isPublic: isPublic
            )
            documentsLoaded.insert(doc, at: 0)
            selectedDocumentID = doc.id
            error = nil
            return doc
        } catch {
            self.error = error
            return nil
        }
    }

    /// Creates a new document seeded from a client-side `DocumentTemplate`
    /// (work-consolidation.md). The chosen template supplies the starter
    /// Markdown body; the title defaults to the template name but the caller
    /// may override it, and the user can rename it in the editor afterward.
    ///
    /// This routes through the same `createDocument(title:body:isPublic:)` path
    /// as a blank document — a template is purely a seed, so seeding from
    /// `.blank` is identical to today's "new blank document" behavior. There is
    /// no templates endpoint; the catalog is bundled in `InterlinedDomain`. If
    /// the API later exposes templates this can switch to a server fetch without
    /// changing this signature.
    @discardableResult
    func createDocument(
        from template: DocumentTemplate,
        title: String? = nil,
        isPublic: Bool = false
    ) async -> Document? {
        let resolvedTitle = title ?? template.name
        return await createDocument(
            title: resolvedTitle,
            body: template.bodyMarkdown,
            isPublic: isPublic
        )
    }

    /// Deletes a document. Optimistic — removes from the rendered list
    /// first, then calls the service; on failure restores the snapshot
    /// and surfaces the error.
    func deleteDocument(id: Document.ID) async {
        let snapshot = documentsLoaded
        documentsLoaded.removeAll { $0.id == id }
        if selectedDocumentID == id { selectedDocumentID = nil }
        do {
            try await documents.delete(id: id)
            error = nil
        } catch {
            documentsLoaded = snapshot
            self.error = error
        }
    }

    /// Replaces an in-list document with `document` (typically after an
    /// edit elsewhere in the app). No service call.
    func replaceDocument(_ document: Document) {
        guard let index = documentsLoaded.firstIndex(where: { $0.id == document.id }) else { return }
        documentsLoaded[index] = document
    }

    // MARK: - Event-bus consumption

    /// Applies a `DocumentSyncEvent` to the rendered list. Pure local
    /// mutation — no networking — except for `deltaApplied` which
    /// reloads the visible folder so newly-inserted documents and
    /// freshly-deleted ones appear without the consumer having to
    /// trigger a refresh manually.
    func apply(event: DocumentSyncEvent) async {
        switch event {
        case .deltaApplied(_, _, let deletedIds):
            // Drop any deleted document from the rendered list — the
            // sync engine has already removed them from the cache.
            // Then refresh so newly-inserted ones for the same folder
            // appear without the user having to refresh manually.
            for id in deletedIds {
                documentsLoaded.removeAll { $0.id == id }
                if selectedDocumentID == id { selectedDocumentID = nil }
            }
            await load(reset: true)
        case .conflictResolved, .pushed:
            // The view-level conflict banner consumes `conflictResolved`
            // directly; `pushed` is informational. The list itself
            // doesn't need to mutate for either.
            break
        }
    }

    // MARK: - Internals

    private func load(reset: Bool) async {
        isLoading = true
        if reset { error = nil }
        defer { isLoading = false }
        do {
            let page = try await documents.documents(
                in: folderID,
                limit: Self.pageSize,
                offset: 0
            )
            documentsLoaded = page
            hasMore = page.count == Self.pageSize
            nextOffset = hasMore ? page.count : nil
            error = nil
            lastRefreshedAt = Date()
        } catch {
            self.error = error
        }
    }

    /// Runs the network load and folds the result in. When `cachePainted`
    /// is true the spinner is suppressed (`isRefreshing`) and a failure
    /// keeps the cached documents on screen (`refreshFailed`) rather than
    /// blanking the list. Used by the SWR `reload(in:)` / `refresh()` paths;
    /// `load(reset:)` remains the blocking path the sync event loop uses.
    private func revalidate(cachePainted: Bool) async {
        if cachePainted {
            isRefreshing = true
        } else {
            isLoading = true
            error = nil
        }
        refreshFailed = false
        defer {
            isLoading = false
            isRefreshing = false
        }
        do {
            let page = try await documents.documents(
                in: folderID,
                limit: Self.pageSize,
                offset: 0
            )
            documentsLoaded = page
            hasMore = page.count == Self.pageSize
            nextOffset = hasMore ? page.count : nil
            error = nil
            lastRefreshedAt = Date()
        } catch {
            if cachePainted {
                refreshFailed = true
            } else {
                self.error = error
            }
        }
    }
}
