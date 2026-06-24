// FolderTreeViewModel
//
// Drives the M4 Documents sidebar (PLAN.md §6 M4 — "folder source list").
// Owns the loaded folders, the user's selection, and the loading / error
// state. Reads through `DocumentsServicing` only — no direct API or
// cache access — so unit tests substitute a stub trivially
// (PLAN.md §3, §7).
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

    /// Page size for the folders fetch. Folders are not paged in the
    /// UI today — the request asks for a large page so the entire tree
    /// arrives in one round-trip.
    static let pageSize: Int = 500

    private let documents: DocumentsServicing

    // MARK: - Observable state

    /// Folders loaded so far, in input order. Used to derive
    /// `tree` lazily on each render.
    private(set) var folders: [FolderNode] = []

    /// Currently selected folder id, if any. `nil` means "root" — the
    /// documents list shows unfiled documents.
    var selectedFolderID: FolderNode.ID?

    /// True while a folder-tree round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load / create /
    /// rename / delete. Cleared on the next successful round-trip.
    private(set) var error: Error?

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

    /// First-time load. Resets state. Safe to call repeatedly.
    func initialLoad() async {
        await reload()
    }

    /// Refreshes the folder tree. The toolbar Refresh button (when
    /// added) calls this; the documents-feature event loop also calls
    /// it after a `deltaApplied` event so other windows' folder
    /// edits flow through.
    func refresh() async {
        await reload()
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
        let snapshot = folders
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
            folders = snapshot
            self.error = error
        }
    }

    /// Deletes a folder. Optimistic — removes from the rendered tree
    /// first, then calls the service; on failure restores the snapshot
    /// and surfaces the error.
    func deleteFolder(id: String) async {
        let snapshot = folders
        folders.removeAll { $0.id == id }
        if selectedFolderID == id { selectedFolderID = nil }
        do {
            try await documents.deleteFolder(id: id)
            error = nil
        } catch {
            folders = snapshot
            self.error = error
        }
    }

    /// Replaces the rendered folder list with `folders`. Used by the
    /// documents event loop to refresh after a `deltaApplied` event
    /// without a refetch.
    func replace(folders: [FolderNode]) {
        self.folders = folders
    }

    // MARK: - Internals

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await documents.folders(limit: Self.pageSize, offset: 0)
            folders = page
            error = nil
        } catch {
            self.error = error
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

    var errorDescription: String? {
        switch self {
        case .invalidFolderName:
            return "Folder name cannot be empty."
        case .invalidDocumentTitle:
            return "Document title cannot be empty."
        case .imageTooLargeAfterPrep:
            return "Image is too large to upload, even after compression."
        }
    }
}
