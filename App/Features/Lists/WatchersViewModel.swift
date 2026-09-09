// WatchersViewModel
//
// Drives `WatchersView` — the M3 sharing panel (PLAN.md §6 M3,
// "List sharing"). Owns the loaded watcher list, the role-edit
// flow, and the add-watcher flow. Role changes and watcher
// adds use the Wave 3 optimistic pattern: snapshot, mutate locally,
// call the service; on success replace with the authoritative return
// value, on failure restore the snapshot and surface the error.
//
// work-consolidation.md G23 (issue #48) changed three things here:
//
//  1. `load()` reads `watchers(of:)` instead of `watcherUsers(of:)`. The
//     `/watchers/users` route is a *candidate search* ("people you could
//     add"), not the watcher list — recon on 2026-09-09 showed it answering
//     `{ users: [...] }` with no `userId` and no `role`, so the panel could
//     never have listed anyone. `/watchers` now decodes its real
//     `{ watchers: [...] }` envelope and carries the nested person object,
//     so it has the display data the panel wants.
//  2. Adding a watcher calls the real `POST /api/lists/{id}/watchers`
//     (`ListsServicing.addWatcher`) instead of re-purposing the role-change
//     `PUT`. That route is subscriber-gated server-side, so a `403` arrives
//     as `ListsError.subscriberRequired` and raises `showSubscriberUpsell` —
//     the same pattern `ShareLinksViewModel` / `InvitesViewModel` use.
//  3. Picking someone to add goes through `watcherCandidates(of:search:)`,
//     the endpoint built for exactly that (it auto-excludes current
//     watchers), replacing the exact-handle lookup.
//
// Per decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class WatchersViewModel {

    /// How many candidates one search page returns. Matches the route's own
    /// documented default so paging behaviour is predictable.
    static let candidatePageSize: Int = 50

    private let lists: ListsServicing
    private let eventBus: ListsEventBus
    let listId: String

    /// Loaded watchers — everyone who currently has access to this list.
    private(set) var watchers: [ListWatcher] = []
    private(set) var isLoading: Bool = false
    private(set) var error: Error?

    /// Candidates matching the most recent search. Empty before the first
    /// search and after a search that matched nobody.
    private(set) var candidates: [CollaboratorCandidate] = []
    /// True while a candidate search is in flight.
    private(set) var isSearching: Bool = false
    /// True once a search has resolved, so the sheet can tell "no results"
    /// apart from "you have not searched yet".
    private(set) var hasSearchedOnce: Bool = false

    /// Raised when an add / role change was blocked because the account is
    /// not a subscriber. The view shows an upsell instead of an error banner.
    private(set) var showSubscriberUpsell: Bool = false

    /// Pending in-flight write set, keyed by `userId`. De-bounces
    /// rapid role changes / remove clicks on the same row.
    private(set) var pendingOperations: Set<String> = []

    init(lists: ListsServicing, eventBus: ListsEventBus, listId: String) {
        self.lists = lists
        self.eventBus = eventBus
        self.listId = listId
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            watchers = try await lists.watchers(of: listId)
        } catch {
            self.error = error
        }
    }

    /// Sets `userId`'s role to `role`. Optimistic flip + rollback.
    func setRole(userId: String, role: WatcherRole) async {
        guard !pendingOperations.contains(userId),
              let index = watchers.firstIndex(where: { $0.userId == userId }) else { return }
        let original = watchers[index]
        let optimistic = ListWatcher(
            userId: original.userId,
            username: original.username,
            displayName: original.displayName,
            avatarURL: original.avatarURL,
            role: role,
            createdAt: original.createdAt
        )
        watchers[index] = optimistic
        pendingOperations.insert(userId)
        defer { pendingOperations.remove(userId) }
        do {
            let confirmed = try await lists.setWatcher(
                listId: listId,
                userId: userId,
                role: role
            )
            // The route answers `{ role }` only, so keep the display fields we
            // already have and take just the server's applied role.
            let authoritative = ListWatcher(
                userId: original.userId,
                username: original.username,
                displayName: original.displayName,
                avatarURL: original.avatarURL,
                role: confirmed.role,
                createdAt: original.createdAt
            )
            if let currentIndex = watchers.firstIndex(where: { $0.userId == userId }) {
                watchers[currentIndex] = authoritative
            }
            eventBus.post(.watcherChanged(listId: listId, watcher: authoritative))
            error = nil
        } catch ListsError.subscriberRequired {
            restore(original)
            showSubscriberUpsell = true
        } catch {
            restore(original)
            self.error = error
        }
    }

    /// Removes `userId` from the watcher list.
    func remove(userId: String) async {
        guard !pendingOperations.contains(userId),
              let index = watchers.firstIndex(where: { $0.userId == userId }) else { return }
        let snapshot = watchers
        watchers.remove(at: index)
        pendingOperations.insert(userId)
        defer { pendingOperations.remove(userId) }
        do {
            try await lists.removeWatcher(listId: listId, userId: userId)
            eventBus.post(.watcherRemoved(listId: listId, userId: userId))
            error = nil
        } catch {
            watchers = snapshot
            self.error = error
        }
    }

    /// Applies a `ListsEvent`. Pure local mutation — keeps multiple
    /// open share panels coherent without a refetch.
    func apply(event: ListsEvent) {
        switch event {
        case .watcherChanged(let id, let watcher) where id == listId:
            if let index = watchers.firstIndex(where: { $0.userId == watcher.userId }) {
                watchers[index] = watcher
            } else {
                watchers.append(watcher)
            }
        case .watcherRemoved(let id, let userId) where id == listId:
            watchers.removeAll { $0.userId == userId }
        default:
            break
        }
    }

    /// Searches people who could be added to this list. A blank query returns
    /// the route's default (unfiltered) page, which is what the picker shows
    /// when it first opens.
    func searchCandidates(query: String) async {
        isSearching = true
        error = nil
        defer {
            isSearching = false
            hasSearchedOnce = true
        }
        do {
            candidates = try await lists.watcherCandidates(
                of: listId,
                search: query,
                limit: Self.candidatePageSize
            )
        } catch {
            candidates = []
            self.error = error
        }
    }

    /// Adds `userId` as a watcher at `role`. Optimistically appends a
    /// provisional row, calls the service, and on failure removes it again.
    ///
    /// `notify` maps to the route's own flag: `true` (the default) emails the
    /// recipient, `false` grants access silently.
    func addWatcher(candidate: CollaboratorCandidate, role: WatcherRole, notify: Bool = true) async {
        let userId = candidate.id
        guard !pendingOperations.contains(userId) else { return }
        guard !watchers.contains(where: { $0.userId == userId }) else {
            error = WatchersError.alreadyWatcher
            return
        }
        let snapshot = watchers
        let provisional = ListWatcher(
            userId: userId,
            username: candidate.username,
            displayName: candidate.displayName,
            avatarURL: candidate.avatar,
            role: role,
            createdAt: nil
        )
        watchers.append(provisional)
        pendingOperations.insert(userId)
        showSubscriberUpsell = false
        defer { pendingOperations.remove(userId) }
        do {
            try await lists.addWatcher(
                listId: listId,
                userId: userId,
                role: role,
                notify: notify
            )
            // The route answers `{ watching: true }` rather than the new row, so
            // the provisional entry *is* the authoritative local state; a later
            // `load()` reconciles it with the server's `createdAt`.
            eventBus.post(.watcherChanged(listId: listId, watcher: provisional))
            // Drop the person from the candidate list so they cannot be added
            // twice before the next search refreshes it.
            candidates.removeAll { $0.id == userId }
            error = nil
        } catch ListsError.subscriberRequired {
            watchers = snapshot
            showSubscriberUpsell = true
        } catch {
            watchers = snapshot
            self.error = error
        }
    }

    /// Dismisses the subscriber upsell.
    func dismissSubscriberUpsell() {
        showSubscriberUpsell = false
    }

    /// Rolls an optimistic role flip back. Re-finds the row by id rather than
    /// trusting the pre-call index — the event bus can reorder `watchers`
    /// while the write is in flight.
    private func restore(_ watcher: ListWatcher) {
        guard let index = watchers.firstIndex(where: { $0.userId == watcher.userId }) else { return }
        watchers[index] = watcher
    }
}

enum WatchersError: LocalizedError, Equatable {
    case alreadyWatcher

    var errorDescription: String? {
        switch self {
        case .alreadyWatcher:
            return "That person already has access to this list."
        }
    }
}
