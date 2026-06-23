// WatchersViewModel
//
// Drives `WatchersView` — the M3 sharing panel (PLAN.md §6 M3,
// "List sharing"). Owns the loaded watcher list and the role-edit
// flow. Per the user's plan answer + `NEXT-WORK.md` NW-1, the M3
// surface is **role-editing-for-existing-watchers only**; the
// "add a user" UX waits for an upstream lookup endpoint.
//
// Role changes use the Wave 3 optimistic pattern: snapshot the
// watcher, flip the role locally, call `setWatcher`; on success
// replace with the service's authoritative return value, on
// failure restore the snapshot and surface the error.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class WatchersViewModel {

    private let lists: ListsServicing
    private let eventBus: ListsEventBus
    let listId: String

    /// Loaded watchers. `watcherUsers` returns the variant with the
    /// username included; we prefer that to the bare `watchers` call
    /// so the share panel always has display data.
    private(set) var watchers: [ListWatcher] = []
    private(set) var isLoading: Bool = false
    private(set) var error: Error?

    /// Pending in-flight write set, keyed by `userId`. De-bounces
    /// rapid role changes / remove clicks on the same row.
    private var pendingOperations: Set<String> = []

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
            watchers = try await lists.watcherUsers(of: listId)
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
            if let currentIndex = watchers.firstIndex(where: { $0.userId == userId }) {
                watchers[currentIndex] = confirmed
            }
            eventBus.post(.watcherChanged(listId: listId, watcher: confirmed))
            error = nil
        } catch {
            if let rollbackIndex = watchers.firstIndex(where: { $0.userId == userId }) {
                watchers[rollbackIndex] = original
            }
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
            }
        case .watcherRemoved(let id, let userId) where id == listId:
            watchers.removeAll { $0.userId == userId }
        default:
            break
        }
    }
}
