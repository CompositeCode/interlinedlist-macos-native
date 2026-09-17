// PublicUserListsViewModel
//
// Drives the public-lists column on a profile (GitHub #44 / G32). The web
// profile shows a Public Lists column with a Watch button per list; macOS had
// no lists on a profile at all.
//
// The route is `GET /api/users/{username}/lists`, confirmed live 2026-09-15:
//
//     {"lists":[…],"pagination":{"total":0,"limit":100,"offset":0,"hasMore":false}}
//
// That is the route the issue recorded as *"still needs probing"*. It is the
// public browse collection — distinct from `GET /api/lists/watching`, which is
// the caller's own *watched* surface and a different thing.
//
// Watching is deliberately **optimistic with rollback**: the button flips the
// moment it is pressed and flips back if the write fails, because a list you
// just watched staying unwatched for a round-trip reads as a broken button.
//
// Reads through `ListsServicing` only. Per decision 0003, this view model
// consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class PublicUserListsViewModel {

    private let lists: ListsServicing

    /// Page size. The live route defaults to 100 and a profile column showing
    /// more than this is a scrolling problem, not a paging one.
    static let pageSize = 50

    // MARK: - Observable state

    /// The handle whose lists are loaded, `nil` before the first load.
    private(set) var username: String?

    private(set) var listsLoaded: [ListSummary] = []

    private(set) var isLoading: Bool = false

    private(set) var error: Error?

    /// True once a load has completed for the current handle, successfully or
    /// not. Separates "this user publishes no lists" from "we have not asked",
    /// which are indistinguishable from `listsLoaded` alone.
    private(set) var hasLoaded: Bool = false

    /// Ids the caller now watches, from this session's own Watch presses.
    ///
    /// Not a read of server state: the public lists route says nothing about
    /// whether *you* watch a list, and asking per row would be N requests for a
    /// button. So this is a record of what was pressed here, and the button
    /// starts neutral for every row on load.
    private(set) var watchedIDs: Set<String> = []

    /// Ids with a watch write in flight, so the row can disable itself rather
    /// than queue duplicate writes.
    private(set) var pendingWatchIDs: Set<String> = []

    /// The error from the most recent failed watch, keyed by list id, so a
    /// failure reports against the row that caused it rather than the column.
    private(set) var watchErrors: [String: String] = [:]

    var isEmpty: Bool { listsLoaded.isEmpty }

    // MARK: - Init

    init(lists: ListsServicing) {
        self.lists = lists
    }

    // MARK: - Intents

    func load(username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // A repeat load for the same handle is a refresh, not a no-op — the
        // profile view's `task(id:)` re-runs on handle changes only.
        if self.username != trimmed {
            listsLoaded = []
            watchedIDs = []
            watchErrors = [:]
            hasLoaded = false
        }
        self.username = trimmed
        isLoading = true
        error = nil
        defer { isLoading = false; hasLoaded = true }

        do {
            let page = try await lists.publicLists(
                username: trimmed,
                limit: Self.pageSize,
                offset: 0
            )
            listsLoaded = page.lists
        } catch {
            self.error = error
            listsLoaded = []
        }
    }

    /// Subscribes the signed-in user to `list`.
    ///
    /// Optimistic: the row flips immediately and rolls back on failure. The
    /// rollback matters more than the optimism — a button that claims success
    /// and silently did nothing is worse than a slow one.
    func watch(listID: String) async {
        guard !pendingWatchIDs.contains(listID), !watchedIDs.contains(listID) else { return }
        pendingWatchIDs.insert(listID)
        watchErrors[listID] = nil
        watchedIDs.insert(listID)
        defer { pendingWatchIDs.remove(listID) }

        do {
            try await lists.watch(listId: listID)
        } catch {
            watchedIDs.remove(listID)
            watchErrors[listID] = error.localizedDescription
        }
    }

    func isWatching(_ listID: String) -> Bool { watchedIDs.contains(listID) }
    func isWatchPending(_ listID: String) -> Bool { pendingWatchIDs.contains(listID) }
}
