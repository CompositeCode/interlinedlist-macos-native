// WatchersViewModel
//
// Drives `WatchersView` — the M3 sharing panel (PLAN.md §6 M3,
// "List sharing"). Owns the loaded watcher list, the role-edit
// flow, and the add-watcher (NW-1) flow. Role changes and watcher
// adds use the Wave 3 optimistic pattern: snapshot, mutate locally,
// call the service; on success replace with the authoritative return
// value, on failure restore the snapshot and surface the error.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class WatchersViewModel {

    private let lists: ListsServicing
    private let userService: UserServicing
    private let eventBus: ListsEventBus
    let listId: String

    /// Loaded watchers. `watcherUsers` returns the variant with the
    /// username included; we prefer that to the bare `watchers` call
    /// so the share panel always has display data.
    private(set) var watchers: [ListWatcher] = []
    private(set) var isLoading: Bool = false
    private(set) var error: Error?

    /// The user found by the last `lookupAndAdd` call. Nil when no search has run
    /// or when the handle was not found. The add-watcher sheet reads this.
    private(set) var foundUser: UserSearchResult?
    /// True while a handle lookup is in flight.
    private(set) var isLookingUp: Bool = false

    /// Pending in-flight write set, keyed by `userId`. De-bounces
    /// rapid role changes / remove clicks on the same row.
    private(set) var pendingOperations: Set<String> = []

    init(lists: ListsServicing, userService: UserServicing, eventBus: ListsEventBus, listId: String) {
        self.lists = lists
        self.userService = userService
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

    /// Looks up a user by exact handle. Populates `foundUser` on success;
    /// sets `foundUser = nil` and `error` when not found or on upstream failure.
    func lookupAndAdd(handle: String) async {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLookingUp = true
        foundUser = nil
        error = nil
        defer { isLookingUp = false }
        do {
            foundUser = try await userService.lookupUser(handle: trimmed)
            if foundUser == nil {
                error = WatchersError.userNotFound(trimmed)
            }
        } catch {
            self.error = error
        }
    }

    /// Adds the looked-up user as a watcher with the given role. Optimistically
    /// appends a provisional row, calls `setWatcher`, and on success replaces it
    /// with the server's authoritative return value. On failure, removes the
    /// provisional row and surfaces the error.
    func addWatcher(userId: String, role: WatcherRole) async {
        guard !pendingOperations.contains(userId) else { return }
        guard !watchers.contains(where: { $0.userId == userId }) else {
            error = WatchersError.alreadyWatcher
            return
        }
        let snapshot = watchers
        let provisional = ListWatcher(userId: userId, username: foundUser?.username, role: role, createdAt: nil)
        watchers.append(provisional)
        pendingOperations.insert(userId)
        defer { pendingOperations.remove(userId) }
        do {
            let confirmed = try await lists.setWatcher(listId: listId, userId: userId, role: role)
            if let idx = watchers.firstIndex(where: { $0.userId == userId }) {
                watchers[idx] = confirmed
            }
            eventBus.post(.watcherChanged(listId: listId, watcher: confirmed))
            foundUser = nil
            error = nil
        } catch {
            watchers = snapshot
            self.error = error
        }
    }
}

enum WatchersError: LocalizedError, Equatable {
    case userNotFound(String)
    case alreadyWatcher

    var errorDescription: String? {
        switch self {
        case .userNotFound(let handle):
            return "@\(handle) was not found."
        case .alreadyWatcher:
            return "That user is already watching this list."
        }
    }
}
