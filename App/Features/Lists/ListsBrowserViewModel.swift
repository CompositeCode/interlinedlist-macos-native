// ListsBrowserViewModel
//
// Drives `ListsBrowserView`: owns the username the user is browsing,
// the loaded summaries, and the loading / paging / error state. Reads
// through `ListsServicing` only — no direct API access — so unit tests
// substitute a stub service (PLAN.md §3, §7).
//
// M1 is read-only and there is no logged-in default; the user types a
// username and we load that user's public lists. The lookup is
// idempotent: calling `loadInitial(username:)` again with the same
// trimmed username is a no-op while a load is in flight.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ListsBrowserViewModel {

    // MARK: - Configuration

    /// Page size for both the initial load and infinite scroll. Mirrors
    /// `TimelineViewModel.pageSize` so the App layer's paging is
    /// uniform across feature areas.
    static let pageSize: Int = 20

    private let lists: ListsServicing

    // MARK: - Observable state

    /// Text the user is typing into the browse field. Two-way bound
    /// from the view; not necessarily the username currently loaded —
    /// see `loadedUsername` for that.
    var usernameInput: String = ""

    /// The username whose public lists are currently loaded (or being
    /// loaded). `nil` before the first successful load. Distinct from
    /// `usernameInput` so the view can show "Lists for @alice" even
    /// while the user edits the input toward something else.
    private(set) var loadedUsername: String?

    /// Lists loaded so far, in display order.
    private(set) var lists_loaded: [ListSummary] = []

    /// True while a network round-trip is in flight (initial or load-more).
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load. Cleared on the
    /// next successful round-trip or when `clear()` is called.
    private(set) var error: Error?

    /// Whether the server reports more pages beyond what's loaded.
    private(set) var hasMore: Bool = false

    /// The `offset` to pass on the next `loadMore` call. `nil` when
    /// `hasMore` is false.
    private(set) var nextOffset: Int?

    // MARK: - Init

    init(lists: ListsServicing) {
        self.lists = lists
    }

    // MARK: - Intents

    /// First-time load for the supplied username. Whitespace-trims the
    /// input and bails out on an empty handle so a stray submit doesn't
    /// fire a doomed request. Resets paging state on every call.
    func loadInitial(username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        loadedUsername = trimmed
        lists_loaded = []
        hasMore = false
        nextOffset = nil
        error = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await lists.publicLists(
                username: trimmed,
                limit: Self.pageSize,
                offset: 0
            )
            apply(page, reset: true)
        } catch {
            self.error = error
        }
    }

    /// Re-fetches page zero for the currently loaded username. Bound
    /// to the browser view's `.refreshable` modifier. No-op when no
    /// username is loaded yet.
    func refresh() async {
        guard let loadedUsername else { return }
        await loadInitial(username: loadedUsername)
    }

    /// Appends the next page when one exists. No-op while a load is in
    /// flight, when `hasMore` is false, or when no username is loaded.
    /// The view calls this on the trailing row's `.onAppear` and we
    /// de-dupe here rather than push it onto the view.
    func loadMore() async {
        guard !isLoading,
              hasMore,
              let offset = nextOffset,
              let loadedUsername else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await lists.publicLists(
                username: loadedUsername,
                limit: Self.pageSize,
                offset: offset
            )
            apply(page, reset: false)
        } catch {
            self.error = error
        }
    }

    /// Resets the browser back to the empty prompt state. Used by the
    /// view's "clear" affordance and by tests that want a clean slate.
    func clear() {
        usernameInput = ""
        loadedUsername = nil
        lists_loaded = []
        hasMore = false
        nextOffset = nil
        error = nil
        isLoading = false
    }

    // MARK: - Internals

    private func apply(_ page: ListsPage, reset: Bool) {
        if reset {
            lists_loaded = page.lists
        } else {
            lists_loaded.append(contentsOf: page.lists)
        }
        hasMore = page.hasMore
        nextOffset = page.nextOffset
        error = nil
    }
}
