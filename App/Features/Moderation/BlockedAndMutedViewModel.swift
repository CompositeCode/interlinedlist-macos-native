// BlockedAndMutedViewModel
//
// Drives `BlockedAndMutedView`: the Settings "Blocked & Muted" pane
// (the-gaps.md G2). Owns the two rendered rosters (blocked / muted), the
// loading / error state, and the unblock / unmute actions. Reads through
// `ModerationServicing` only — no direct API access — so unit tests
// substitute a stub service.
//
// Unblock / unmute use the project's optimistic-removal pattern (mirrors
// `OwnedListsViewModel.deleteList`): snapshot the roster, remove the row
// locally, call the service, and on failure restore the snapshot and
// surface the error. A per-username debounce set guards against a rapid
// double tap firing the service twice for the same row.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class BlockedAndMutedViewModel {

    // MARK: - Dependencies

    private let service: ModerationServicing

    // MARK: - Observable state

    /// Accounts the current user has blocked, in server order.
    private(set) var blocked: [ModeratedUser] = []

    /// Accounts the current user has muted, in server order.
    private(set) var muted: [ModeratedUser] = []

    /// True while a load round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load / unblock / unmute.
    /// Cleared on the next successful round-trip.
    private(set) var error: Error?

    /// True once the first load has resolved (success or failure). Lets
    /// the view distinguish first-render shimmer from a genuinely empty
    /// roster.
    private(set) var hasLoadedOnce: Bool = false

    /// Per-username debounce set so a rapid double-tap on an unblock /
    /// unmute row does not double-fire the service call.
    private var pendingOperations: Set<String> = []

    // MARK: - Init

    init(service: ModerationServicing) {
        self.service = service
    }

    // MARK: - Intents

    /// First-time + pull-to-refresh load. Fetches both rosters
    /// concurrently and replaces the rendered rows.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let blockedUsers = service.blockedUsers()
            async let mutedUsers = service.mutedUsers()
            blocked = try await blockedUsers
            muted = try await mutedUsers
            error = nil
            hasLoadedOnce = true
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
    }

    /// Unblocks a user. Optimistic: remove the row locally, call the
    /// service, restore the snapshot on failure. Idempotent — a username
    /// with an in-flight operation is a no-op.
    func unblock(username: String) async {
        guard !pendingOperations.contains(username) else { return }
        guard let index = blocked.firstIndex(where: { $0.username == username }) else { return }
        pendingOperations.insert(username)
        defer { pendingOperations.remove(username) }
        let snapshot = blocked
        blocked.remove(at: index)
        do {
            try await service.unblock(username: username)
            error = nil
        } catch {
            blocked = snapshot
            self.error = error
        }
    }

    /// Unmutes a user. Same optimistic-removal shape as `unblock`.
    func unmute(username: String) async {
        guard !pendingOperations.contains(username) else { return }
        guard let index = muted.firstIndex(where: { $0.username == username }) else { return }
        pendingOperations.insert(username)
        defer { pendingOperations.remove(username) }
        let snapshot = muted
        muted.remove(at: index)
        do {
            try await service.unmute(username: username)
            error = nil
        } catch {
            muted = snapshot
            self.error = error
        }
    }

    /// Convenience for tests + previews — seed the rendered rosters
    /// without going through the service.
    func seedForTest(blocked: [ModeratedUser], muted: [ModeratedUser]) {
        self.blocked = blocked
        self.muted = muted
        self.hasLoadedOnce = true
    }
}
