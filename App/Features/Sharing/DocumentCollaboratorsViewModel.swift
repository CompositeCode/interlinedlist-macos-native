// DocumentCollaboratorsViewModel
//
// Drives `DocumentCollaboratorsView` — the "Document Access & Permissions"
// section of the web sharing dialog (work-consolidation.md G3), the document
// analogue of a list's watchers. Owns the loaded collaborators ("Users with
// access"), the user-search form (query → candidates), the "role for new
// users" + "email this person" choices, and the add / change-role / remove
// intents. Reads through `SharingServicing` only — no direct API or
// entitlements access — so unit tests substitute a stub service.
//
// Subscriber gate: adding a collaborator and changing a role are
// subscriber-only. The domain service throws `SharingError.subscriberRequired`
// before any HTTP when the account is not a subscriber; this view model
// catches that specific case and raises `showSubscriberUpsell` instead of
// surfacing a raw error (mirrors `ShareLinksViewModel`). Listing, searching,
// and removing are not gated, so a downgraded owner can still prune access.
//
// Optimistic mutation: add inserts the new row immediately, change-role
// rewrites the row in place, and remove prunes it; each calls the service and
// restores the pre-mutation snapshot on failure (the proven M2 pattern). A
// per-user debounce set guards a rapid double-tap on role/remove.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class DocumentCollaboratorsViewModel {

    // MARK: - Dependencies

    private let service: SharingServicing
    let documentId: String

    // MARK: - Observable state

    /// People who already have per-person access — roots the "Users with
    /// access" table.
    private(set) var collaborators: [Collaborator] = []

    /// The latest user-search results, eligible to be granted access.
    private(set) var searchResults: [CollaboratorCandidate] = []

    /// True while the initial load / a refresh round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// True while a user-search round-trip is in flight.
    private(set) var isSearching: Bool = false

    /// True while an add round-trip is in flight (drives the form's disabled
    /// state independently of a background refresh).
    private(set) var isAdding: Bool = false

    /// Surfaced error from the most recent failed load / search / add /
    /// set-role / remove. The subscriber-gate case is routed to
    /// `showSubscriberUpsell` instead, so this never carries a
    /// `subscriberRequired`.
    private(set) var error: Error?

    /// Raised when an add / set-role was blocked because the account is not a
    /// subscriber. The view presents an upsell instead of an error banner.
    private(set) var showSubscriberUpsell: Bool = false

    /// True once the first load has resolved (success or failure). Lets the
    /// view distinguish "loading" from "no collaborators yet".
    private(set) var hasLoadedOnce: Bool = false

    // MARK: - Form state (bound by the view)

    /// The current search text. Bound to the search field.
    var searchQuery: String = ""

    /// The role granted to the next added user. Bound to "Role for new users".
    var newRole: ShareRole = .watcher

    /// Whether adding a user also sends them an email invite ("Email this
    /// person"). Off shares silently (in-app notification only).
    var notify: Bool = true

    // MARK: - Internals

    /// Per-user debounce sets so a rapid double-tap on a role change / remove
    /// doesn't double-fire the service call (proven M2 pattern).
    private var pendingRoleChanges: Set<String> = []
    private var pendingRemovals: Set<String> = []

    // MARK: - Init

    init(service: SharingServicing, documentId: String) {
        self.service = service
        self.documentId = documentId
    }

    // MARK: - Intents

    /// First-time + refresh load. Replaces the rendered access list with the
    /// server's authoritative set.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            collaborators = try await service.documentCollaborators(documentId: documentId)
            error = nil
            hasLoadedOnce = true
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
    }

    /// Runs the user search for the current `searchQuery`. A blank query is
    /// rejected before any HTTP — the results are cleared and no service call
    /// is made.
    func search() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        guard !isSearching else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await service.searchDocumentCollaborators(documentId: documentId, query: trimmed)
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Clears the search text and results (e.g., after adding a user).
    func clearSearch() {
        searchQuery = ""
        searchResults = []
    }

    /// Grants `candidate` access at the current `newRole`, emailing them when
    /// `notify` is on. Optimistic: the new row is inserted immediately, then
    /// the service is called; a `subscriberRequired` failure raises the upsell
    /// and rolls back, any other failure rolls back and surfaces the error. A
    /// candidate who already has access is a no-op (no service call).
    func add(candidate: CollaboratorCandidate) async {
        guard !isAdding else { return }
        guard !collaborators.contains(where: { $0.userId == candidate.id }) else { return }
        showSubscriberUpsell = false
        isAdding = true
        defer { isAdding = false }

        let snapshot = collaborators
        let optimistic = Collaborator(
            userId: candidate.id,
            role: newRole,
            username: candidate.username,
            displayName: candidate.displayName,
            avatar: candidate.avatar,
            createdAt: nil
        )
        collaborators.append(optimistic)
        do {
            try await service.addDocumentCollaborator(
                documentId: documentId,
                userId: candidate.id,
                role: newRole,
                notify: notify
            )
            error = nil
            clearSearch()
        } catch SharingError.subscriberRequired {
            collaborators = snapshot
            showSubscriberUpsell = true
        } catch {
            collaborators = snapshot
            self.error = error
        }
    }

    /// Changes an existing collaborator's role. Optimistic: rewrite the row in
    /// place, call the service, restore the snapshot on failure. A role change
    /// does not re-notify the user. The per-user debounce guards a double-tap.
    func setRole(userId: String, role: ShareRole) async {
        guard !pendingRoleChanges.contains(userId) else { return }
        guard let index = collaborators.firstIndex(where: { $0.userId == userId }) else { return }
        guard collaborators[index].role != role else { return }
        pendingRoleChanges.insert(userId)
        defer { pendingRoleChanges.remove(userId) }

        let snapshot = collaborators
        collaborators[index] = Self.withRole(collaborators[index], role: role)
        do {
            try await service.setDocumentCollaboratorRole(
                documentId: documentId,
                userId: userId,
                role: role,
                notify: false
            )
            error = nil
        } catch SharingError.subscriberRequired {
            collaborators = snapshot
            showSubscriberUpsell = true
        } catch {
            collaborators = snapshot
            self.error = error
        }
    }

    /// Removes a collaborator. Optimistic: prune the row, call the service,
    /// restore the snapshot when the server reports it was not removed or the
    /// call fails. The per-user debounce guards a double-tap.
    func remove(userId: String) async {
        guard !pendingRemovals.contains(userId) else { return }
        pendingRemovals.insert(userId)
        defer { pendingRemovals.remove(userId) }

        let snapshot = collaborators
        collaborators.removeAll { $0.userId == userId }
        do {
            let removed = try await service.removeDocumentCollaborator(documentId: documentId, userId: userId)
            if removed {
                error = nil
            } else {
                collaborators = snapshot
            }
        } catch {
            collaborators = snapshot
            self.error = error
        }
    }

    /// Dismisses the subscriber upsell.
    func dismissUpsell() {
        showSubscriberUpsell = false
    }

    // MARK: - Test seams

    /// Convenience for tests + previews — seed the rendered access list without
    /// a service round-trip.
    func seedForTest(collaborators: [Collaborator]) {
        self.collaborators = collaborators
        self.hasLoadedOnce = true
    }

    // MARK: - Pure helpers

    /// Returns a copy of `collaborator` with a different role (the model is
    /// immutable, so a role change rebuilds the value). Pure.
    private static func withRole(_ collaborator: Collaborator, role: ShareRole) -> Collaborator {
        Collaborator(
            userId: collaborator.userId,
            role: role,
            username: collaborator.username,
            displayName: collaborator.displayName,
            avatar: collaborator.avatar,
            createdAt: collaborator.createdAt
        )
    }
}
