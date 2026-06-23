// OwnedListsViewModel
//
// Drives `OwnedListsRootView`: owns the loaded owned lists, the
// selection, paging, and the loading / error state. Reads through
// `ListsServicing` only — no direct API or cache access — so unit
// tests substitute a stub service trivially (PLAN.md §3, §7).
//
// M3 surface (PLAN.md §6 M3):
// - `initialLoad` / `refresh` / `loadMore` for the signed-in user's
//   lists (`/api/lists`).
// - `deleteList(id:)` for context-menu deletes — local removal first,
//   API call, no rollback (the API call is idempotent and a refetch
//   on retry surfaces the truth).
// - `refreshList(id:)` for GitHub-backed refresh — surfaced as a
//   toolbar button enabled only when the selected list is GitHub-
//   backed.
// - `apply(event:)` consumes the `ListsEventBus` so writes from
//   sheets or other open windows mutate the rendered list in place
//   without a refetch.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class OwnedListsViewModel {

    // MARK: - Configuration

    /// Page size for the owned-lists fetch. Matches the other view
    /// models so the App layer's paging defaults are uniform.
    static let pageSize: Int = 50

    private let lists: ListsServicing

    // MARK: - Observable state

    /// Lists loaded so far, in display order.
    private(set) var lists_loaded: [OwnedList] = []
    /// Currently selected list id, if any. Drives the detail column
    /// and the GitHub-refresh button's enabled state.
    var selectedListID: String?
    /// True while a network round-trip is in flight (initial, refresh,
    /// load-more, or refresh-of-list).
    private(set) var isLoading: Bool = false
    /// Surfaced error from the most recent failed load / delete /
    /// refresh. Cleared on the next successful round-trip.
    private(set) var error: Error?
    /// Whether the server reports more pages beyond what's loaded.
    private(set) var hasMore: Bool = false
    /// The `offset` to pass on the next `loadMore` call. `nil` when
    /// `hasMore` is false.
    private(set) var nextOffset: Int?

    /// Currently selected list, if any. Computed lazily so the view
    /// can render the toolbar / refresh button based on its source.
    var selectedList: OwnedList? {
        guard let selectedListID else { return nil }
        return lists_loaded.first { $0.id == selectedListID }
    }

    // MARK: - Init

    init(lists: ListsServicing) {
        self.lists = lists
    }

    // MARK: - Intents

    /// First-time load. Resets paging state. Safe to call repeatedly.
    func initialLoad() async {
        await load(reset: true)
    }

    /// Refreshes the owned-lists list (the toolbar Refresh button when
    /// no GitHub-backed selection is active).
    func refresh() async {
        await load(reset: true)
    }

    /// Appends the next page when one exists. No-op while a load is
    /// in flight or when `hasMore` is false.
    func loadMore() async {
        guard !isLoading, hasMore, let offset = nextOffset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await lists.myLists(limit: Self.pageSize, offset: offset)
            apply(page, reset: false)
        } catch {
            self.error = error
        }
    }

    /// Selects a list by id. Distinct from the bindable `selectedListID`
    /// so callers can clear the selection programmatically too.
    func select(id: String?) {
        selectedListID = id
    }

    /// Deletes a list. Removes from the rendered list first, then calls
    /// the service; on failure restores the snapshot and surfaces the
    /// error (mirrors the Wave 3 optimistic pattern).
    func deleteList(id: String) async {
        guard let index = lists_loaded.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = lists_loaded
        lists_loaded.remove(at: index)
        if selectedListID == id { selectedListID = nil }
        do {
            try await lists.delete(listId: id)
            error = nil
        } catch {
            lists_loaded = snapshot
            self.error = error
        }
    }

    /// Triggers a GitHub-backed refresh of `listId`. Updates the cached
    /// `OwnedList` in place with the service's freshly-refreshed copy.
    func refreshList(id: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let refreshed = try await lists.refresh(listId: id)
            if let index = lists_loaded.firstIndex(where: { $0.id == id }) {
                lists_loaded[index] = refreshed
            }
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Whether the toolbar's GitHub-refresh button should be enabled.
    /// Per PLAN.md §6 M3 + the user's plan answer (manual-only refresh),
    /// only enable for the selected list when it has a `GitHubListSource`.
    var canRefreshSelectedList: Bool {
        selectedList?.gitHubSource != nil
    }

    // MARK: - Nested-list helper

    /// Returns the root-level lists (those with no parent) in display
    /// order. The sidebar disclosure tree starts here and recurses via
    /// `children(of:)`.
    func roots() -> [OwnedList] {
        lists_loaded.filter { $0.parentID == nil }
    }

    /// Returns the direct children of `parentID` in display order.
    func children(of parentID: String) -> [OwnedList] {
        lists_loaded.filter { $0.parentID == parentID }
    }

    // MARK: - Event-bus consumption

    /// Applies a `ListsEvent` to the rendered list. Pure local mutation
    /// — no networking. Called by the view when the bus yields a new
    /// event so writes elsewhere reflect here.
    func apply(event: ListsEvent) {
        switch event {
        case .listCreated(let list):
            if !lists_loaded.contains(where: { $0.id == list.id }) {
                lists_loaded.insert(list, at: 0)
            }
        case .listUpdated(let list):
            if let index = lists_loaded.firstIndex(where: { $0.id == list.id }) {
                lists_loaded[index] = list
            }
        case .listDeleted(let id):
            lists_loaded.removeAll { $0.id == id }
            if selectedListID == id { selectedListID = nil }
        case .rowCreated, .rowUpdated, .rowDeleted,
             .schemaChanged,
             .watcherChanged, .watcherRemoved,
             .connectionAdded, .connectionRemoved:
            // Sidebar-level view model only tracks list-level events.
            break
        }
    }

    // MARK: - Internals

    private func load(reset: Bool) async {
        if reset {
            lists_loaded = []
            hasMore = false
            nextOffset = nil
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await lists.myLists(limit: Self.pageSize, offset: 0)
            apply(page, reset: true)
        } catch {
            self.error = error
        }
    }

    private func apply(_ page: OwnedListsPage, reset: Bool) {
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
