// PublicUserDocumentsViewModel
//
// Drives the documents column on a public profile (work-consolidation.md
// G24 — `GET /api/users/{username}/documents`). The web profile has a
// documents tab; macOS had nothing.
//
// The route is unauthenticated, so this works for any handle and while
// signed out. It is deliberately load-on-demand rather than eager: a profile
// view that fires a second request for every handle typed into the browse
// field would triple the traffic of scanning profiles.
//
// Reads through `DocumentsServicing` only. Per decision 0003, this view model
// consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class PublicUserDocumentsViewModel {

    private let documents: DocumentsServicing

    // MARK: - Observable state

    /// The handle whose documents are loaded, `nil` before the first load.
    private(set) var username: String?

    /// The loaded public documents, in server order.
    private(set) var documentsLoaded: [Document] = []

    /// Public folders the route reported. Empty on every account reachable
    /// during the G24 probe; surfaced rather than dropped so a future
    /// server-side change is visible instead of silently ignored.
    private(set) var folders: [FolderNode] = []

    /// True while a round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load. Cleared on the next
    /// successful one.
    private(set) var error: Error?

    /// True once a load has completed (successfully or not) for the current
    /// handle. Separates "this user has published nothing" from "we have not
    /// asked yet", which look identical on `documentsLoaded` alone.
    private(set) var hasLoaded: Bool = false

    /// True when the user has published nothing. Only meaningful after
    /// `hasLoaded`.
    var isEmpty: Bool {
        documentsLoaded.isEmpty && folders.isEmpty
    }

    // MARK: - Init

    init(documents: DocumentsServicing) {
        self.documents = documents
    }

    // MARK: - Intents

    /// Loads `username`'s public documents. Refuses a blank handle before the
    /// service call — the empty path would resolve to a different route
    /// entirely — and resets the previous user's rows so a failed load never
    /// shows the last user's documents under the new name.
    func load(username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = DocumentsUIError.invalidUsername
            hasLoaded = false
            documentsLoaded = []
            folders = []
            self.username = nil
            return
        }
        // Switching handles clears the old rows immediately: attributing one
        // user's documents to another, even for one frame, is worse than a
        // blank column.
        if self.username != trimmed {
            documentsLoaded = []
            folders = []
            hasLoaded = false
        }
        self.username = trimmed
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await documents.publicDocuments(ofUser: trimmed)
            documentsLoaded = result.documents
            folders = result.folders
            error = nil
        } catch {
            // Keep the column empty on failure rather than stale — see above.
            documentsLoaded = []
            folders = []
            self.error = error
        }
        hasLoaded = true
    }

    /// Re-runs the load for the currently-loaded handle. No-op before the
    /// first successful `load(username:)`.
    func refresh() async {
        guard let username else { return }
        await load(username: username)
    }

    /// Drops everything, returning the column to its pre-load state. Called
    /// when the host profile view clears its results.
    func clear() {
        username = nil
        documentsLoaded = []
        folders = []
        error = nil
        hasLoaded = false
    }
}
