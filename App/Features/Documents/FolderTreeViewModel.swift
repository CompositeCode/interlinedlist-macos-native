// FolderTreeViewModel
//
// Drives the M4 Documents sidebar (PLAN.md §6 M4 — "folder source list").
// Owns the loaded folders, the user's selection, and the loading / error
// state. Reads through `DocumentsServicing` only — no direct API or
// cache access — so unit tests substitute a stub trivially
// (PLAN.md §3, §7).
//
// work-consolidation.md G24: the sidebar is now built from **one** call.
// `documents.documentTree()` (`GET /api/documents/tree`) returns every folder
// with its documents inline plus the unfiled root documents, so the folder
// fetch and the per-folder document counts arrive together where the folder
// list used to be one call and counts were simply unavailable.
//
// Two things the tree does *not* retire, verified against the live shape
// before the swap: its inline document rows carry no body and no `updatedAt`,
// so `DocumentsListViewModel` keeps its own `documents(in:)` fetch for the
// middle column and the editor keeps its own read. The tree's summaries are
// used for counts, for the "move to folder" destination list, and to identify
// the machine-managed `_templates` folder — never as documents to open.
//
// "Root" (no selected folder) is a first-class state: when
// `selectedFolderID == nil`, the documents list shows top-level
// (unfiled) documents.
//
// Decision 0003 compliance: this file consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class FolderTreeViewModel {

    /// Retained page size for the legacy `documents.folders(limit:offset:)`
    /// read. The sidebar no longer uses it — `documentTree()` is unpaged and
    /// returns the whole account — but the constant stays public-to-the-target
    /// because other call sites and tests reference it.
    static let pageSize: Int = 500

    private let documents: DocumentsServicing

    // MARK: - Observable state

    /// Folders rendered in the sidebar, in server order. Excludes the
    /// machine-managed `_templates` folder, which the tree returns inline
    /// with the user's own folders but which is not a browsable destination.
    /// Used to derive `tree` lazily on each render.
    private(set) var folders: [FolderNode] = []

    /// The most recent successful `documentTree()` result. Backs the per-folder
    /// document counts and the move-destination list. Empty until the first
    /// network revalidation lands — the cache paint fills `folders` but has no
    /// document membership to offer, so counts stay hidden until then rather
    /// than flashing a wrong zero.
    private(set) var snapshot: DocumentTreeSnapshot = DocumentTreeSnapshot()

    /// Currently selected folder id, if any. `nil` means "root" — the
    /// documents list shows unfiled documents.
    var selectedFolderID: FolderNode.ID?

    /// True while a folder-tree round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// True while a background revalidation runs *after* the cache has
    /// already painted the tree (stale-while-revalidate, PLAN.md §5).
    private(set) var isRefreshing: Bool = false

    /// True when a background revalidation failed while cached folders were
    /// on screen. The tree keeps its cached folders; the view surfaces this
    /// as an unobtrusive hint rather than blanking the sidebar.
    private(set) var refreshFailed: Bool = false

    /// Surfaced error from the most recent failed load / create /
    /// rename / delete. Cleared on the next successful round-trip.
    private(set) var error: Error?

    /// Timestamp of the last successful network refresh — drives the TTL.
    private(set) var lastRefreshedAt: Date?

    /// Freshness window: a re-appearing view whose folders refreshed within
    /// this many seconds skips revalidation and trusts cache.
    static let refreshTTL: TimeInterval = 45

    /// Whether a `.task`-driven re-appearance should revalidate.
    var shouldRefresh: Bool {
        guard let lastRefreshedAt else { return true }
        return Date().timeIntervalSince(lastRefreshedAt) >= Self.refreshTTL
    }

    /// The folders, projected into a parent/children index for sidebar
    /// rendering. Recomputed on every call — cheap (folders are
    /// bounded by user count, not page count).
    var tree: FolderTree {
        FolderTree(folders: folders)
    }

    // MARK: - Init

    init(documents: DocumentsServicing) {
        self.documents = documents
    }

    // MARK: - Intents

    /// First-time load, stale-while-revalidate (PLAN.md §5): paint from the
    /// on-disk cache immediately (no blocking spinner when non-empty), then
    /// revalidate over the network in the background. Cold start (empty
    /// cache) keeps the blocking-spinner behavior. Safe to call repeatedly.
    func initialLoad() async {
        // The cache holds every folder the sync engine has seen, `_templates`
        // included. Filter it the same way the tree paint does so the sidebar
        // doesn't briefly show a folder that then disappears on revalidation.
        let cached = Self.browsable(await documents.cachedFolders())
        let paintedFromCache = !cached.isEmpty
        if paintedFromCache {
            folders = cached
        }
        await revalidate(cachePainted: paintedFromCache)
    }

    /// Refreshes the folder tree. The toolbar Refresh button (when
    /// added) calls this; the documents-feature event loop also calls
    /// it after a `deltaApplied` event so other windows' folder
    /// edits flow through. Always bypasses the TTL.
    func refresh() async {
        await revalidate(cachePainted: !folders.isEmpty)
    }

    /// Selects a folder by id (or `nil` for the unfiled-root view).
    func select(id: FolderNode.ID?) {
        selectedFolderID = id
    }

    /// Creates a new folder under `parentId` (or as a root folder when
    /// `parentId == nil`). On success appends to the loaded list and
    /// returns the new folder so the caller can select it.
    @discardableResult
    func createFolder(name: String, parentId: String?) async -> FolderNode? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Invalid-input case: refuse before hitting the service so
            // the service stays focused on transport-level concerns.
            error = DocumentsUIError.invalidFolderName
            return nil
        }
        do {
            let folder = try await documents.createFolder(name: trimmed, parentId: parentId)
            folders.append(folder)
            error = nil
            return folder
        } catch {
            self.error = error
            return nil
        }
    }

    /// Renames an existing folder. Updates in place on success; on
    /// failure restores the snapshot and surfaces the error (mirrors
    /// the Wave 3 optimistic pattern).
    func renameFolder(id: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = DocumentsUIError.invalidFolderName
            return
        }
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        // Named `previous`, not `snapshot` — `snapshot` is now the tree
        // property on this view model.
        let previous = folders
        // Optimistic update — swap the in-memory copy first.
        let original = folders[index]
        folders[index] = FolderNode(
            id: original.id,
            parentId: original.parentId,
            name: trimmed,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
            deleted: original.deleted
        )
        do {
            let refreshed = try await documents.renameFolder(id: id, to: trimmed)
            if let idx = folders.firstIndex(where: { $0.id == id }) {
                folders[idx] = refreshed
            }
            error = nil
        } catch {
            folders = previous
            self.error = error
        }
    }

    /// Deletes a folder. Optimistic — removes from the rendered tree
    /// first, then calls the service; on failure restores the snapshot
    /// and surfaces the error.
    func deleteFolder(id: String) async {
        let previous = folders
        folders.removeAll { $0.id == id }
        if selectedFolderID == id { selectedFolderID = nil }
        do {
            try await documents.deleteFolder(id: id)
            error = nil
        } catch {
            folders = previous
            self.error = error
        }
    }

    /// Replaces the rendered folder list with `folders`. Used by the
    /// documents event loop to refresh after a `deltaApplied` event
    /// without a refetch.
    func replace(folders: [FolderNode]) {
        self.folders = Self.browsable(folders)
    }

    // MARK: - Derived sidebar data (G24)

    /// How many documents are filed directly in `folderID` — or at root when
    /// `nil` — according to the last successful tree fetch.
    ///
    /// `nil` (rather than `0`) while the snapshot is cold, so a sidebar row
    /// painted from cache shows no badge instead of an authoritative-looking
    /// zero. Direct children only: a parent folder does not count documents in
    /// its sub-folders, because the tree does not nest them that way.
    func documentCount(for folderID: FolderNode.ID?) -> Int? {
        guard hasTreeSnapshot else { return nil }
        return snapshot.documentCount(in: folderID)
    }

    /// True once a `documentTree()` call has landed. Distinguishes "no
    /// documents" from "we have not asked yet".
    var hasTreeSnapshot: Bool {
        lastRefreshedAt != nil
    }

    /// The folders offered as a **Move to folder** destination, in sidebar
    /// order. Never includes `_templates`: it is created and populated by the
    /// server for the template picker, and filing a normal document into it
    /// would make that document show up as a template.
    ///
    /// "No folder (root)" is not in this list — the caller renders it as a
    /// separate `nil` destination.
    var moveDestinations: [FolderNode] {
        // Prefer the rendered folder list so an optimistically-created folder
        // is immediately offered, rather than waiting for the next tree fetch.
        folders
    }

    /// The id of the machine-managed `_templates` folder, when the account has
    /// one. `nil` before the template picker has ever been opened.
    var templatesFolderID: FolderNode.ID? {
        snapshot.templatesFolderID
    }

    /// The folder holding `documentID` per the last tree fetch, and whether the
    /// snapshot knows the document at all. Used by the move action to grey out
    /// the destination the document is already in.
    func currentFolderID(ofDocument documentID: String) -> FolderNode.ID? {
        snapshot.folderID(ofDocument: documentID)
    }

    // MARK: - Internals

    /// Drops the machine-managed `_templates` folder from a folder list.
    /// The tree, the cache and the sync deltas all carry it; none of the three
    /// should put it in the sidebar.
    private static func browsable(_ folders: [FolderNode]) -> [FolderNode] {
        folders.filter { $0.name != DocumentTreeSnapshot.templatesFolderName }
    }

    /// Runs the network load and folds the result in. When `cachePainted`
    /// is true the spinner is suppressed (`isRefreshing`) and a failure
    /// keeps the cached folders on screen (`refreshFailed`) rather than
    /// blanking the sidebar.
    private func revalidate(cachePainted: Bool) async {
        if cachePainted {
            isRefreshing = true
        } else {
            isLoading = true
        }
        refreshFailed = false
        defer {
            isLoading = false
            isRefreshing = false
        }
        do {
            // G24: one call. `documentTree()` carries the folders *and* their
            // document membership, replacing the folders-only fetch that used
            // to sit here.
            let tree = try await documents.documentTree()
            snapshot = tree
            folders = tree.userFolders
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

// MARK: - DocumentsUIError

/// Errors raised by the M4 Documents view models before any service
/// call. Wraps validation-style concerns the service layer doesn't see.
enum DocumentsUIError: Error, Equatable, LocalizedError {
    case invalidFolderName
    case invalidDocumentTitle
    case imageTooLargeAfterPrep
    /// A blank handle was submitted to the public-documents column
    /// (work-consolidation.md G24). Caught in the view model so the empty
    /// path never reaches the network.
    case invalidUsername
    /// A blank invite token was submitted to the invite landing.
    case invalidInviteToken

    var errorDescription: String? {
        switch self {
        case .invalidFolderName:
            return "Folder name cannot be empty."
        case .invalidDocumentTitle:
            return "Document title cannot be empty."
        case .imageTooLargeAfterPrep:
            return "Image is too large to upload, even after compression."
        case .invalidUsername:
            return "Enter a username to see their public documents."
        case .invalidInviteToken:
            return "That doesn't look like an invite link."
        }
    }
}
