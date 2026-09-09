// WatchedListsViewModel
//
// Drives the "Shared with me" section of the Lists sidebar
// (work-consolidation.md G23 / issue #48) — the lists *other people* own and
// gave this account access to, which the web shows as a datagrid on `/lists`
// and macOS had no equivalent of at all.
//
// Deliberately a **separate** view model from `OwnedListsViewModel` rather
// than another array on it. The two collections come from different routes
// with independent failure modes, and the issue's acceptance criteria require
// that a failing `GET /api/lists/watching` leaves the owned lists rendering
// normally. Separate view models make that structural instead of a convention
// somebody has to remember.
//
// Reads through `ListsServicing` only, so unit tests substitute a stub.
//
// Per decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class WatchedListsViewModel {

    /// Page size for the watched-lists fetch. Matches `OwnedListsViewModel`
    /// so the two sidebar sections page identically.
    static let pageSize: Int = 50

    /// Freshness window shared with `OwnedListsViewModel`: a re-appearing view
    /// whose data refreshed within this many seconds skips revalidation.
    static let refreshTTL: TimeInterval = 45

    private let lists: ListsServicing

    // MARK: - Observable state

    /// Lists shared with this account, in the server's order.
    private(set) var watched: [WatchedList] = []

    /// True while a load round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load. Scoped to this
    /// section: the owned-lists sidebar above keeps rendering regardless.
    private(set) var error: Error?

    /// True once the first load resolved, so the view can tell "loading" from
    /// "nobody has shared anything with you".
    private(set) var hasLoadedOnce: Bool = false

    /// Whether the server reports more pages beyond what is loaded.
    private(set) var hasMore: Bool = false

    /// The `offset` for the next `loadMore` call. `nil` when `hasMore` is false.
    private(set) var nextOffset: Int?

    /// Timestamp of the last successful load; drives `shouldRefresh`.
    private(set) var lastRefreshedAt: Date?

    /// Whether a `.task`-driven re-appearance should revalidate.
    var shouldRefresh: Bool {
        guard let lastRefreshedAt else { return true }
        return Date().timeIntervalSince(lastRefreshedAt) >= Self.refreshTTL
    }

    // MARK: - Init

    init(lists: ListsServicing) {
        self.lists = lists
    }

    // MARK: - Derived

    /// Watched lists grouped by the caller's role, so the sidebar can show
    /// "what I can edit" apart from "what I can only read". Roles with no
    /// lists are omitted; within a group the server's order is preserved.
    var groupedByRole: [(role: ShareRole, lists: [WatchedList])] {
        ShareRole.allCases.compactMap { role in
            let matching = watched.filter { $0.role == role }
            return matching.isEmpty ? nil : (role: role, lists: matching)
        }
    }

    /// Looks a watched list up by id — the rows pane resolves the sidebar
    /// selection through this when it is not one of the owned lists.
    func list(withID id: String?) -> WatchedList? {
        guard let id else { return nil }
        return watched.first { $0.id == id }
    }

    // MARK: - Intents

    /// First load / manual refresh. Replaces the whole collection.
    ///
    /// A failure does **not** blank rows already on screen: the section keeps
    /// what it has and surfaces `error` beside it, so a flaky `watching` call
    /// never costs the user their shared lists mid-session.
    func load() async {
        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            let page = try await lists.watching(limit: Self.pageSize, offset: 0)
            watched = page.lists
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            lastRefreshedAt = Date()
        } catch {
            self.error = error
        }
    }

    /// Appends the next page when one exists. No-op while a load is in flight
    /// or when the server reported no more pages.
    func loadMore() async {
        guard !isLoading, hasMore, let offset = nextOffset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await lists.watching(limit: Self.pageSize, offset: offset)
            watched.append(contentsOf: page.lists)
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Applies a `ListsEvent`. Pure local mutation, no networking.
    ///
    /// Only `listDeleted` is meaningful here: a list this account merely
    /// watches cannot be created or renamed from this client, but losing
    /// access (or the owner deleting it) must drop the row. `listCreated` is
    /// deliberately ignored — a list *this* account creates belongs to the
    /// owned section, never here.
    func apply(event: ListsEvent) {
        switch event {
        case .listDeleted(let id):
            watched.removeAll { $0.id == id }
        case .listUpdated(let list):
            if let index = watched.firstIndex(where: { $0.id == list.id }) {
                let existing = watched[index]
                watched[index] = WatchedList(
                    list: list,
                    owner: existing.owner,
                    role: existing.role,
                    parentTitle: existing.parentTitle
                )
            }
        case .listCreated, .rowCreated, .rowUpdated, .rowDeleted,
             .schemaChanged,
             .watcherChanged, .watcherRemoved,
             .connectionAdded, .connectionRemoved:
            break
        }
    }
}
