import Foundation

/// The lists cache port (PLAN.md §5 — "lists read from a SwiftData cache
/// with stale-while-revalidate"). Mirrors `MessageStore`: the domain layer
/// exposes the protocol; the SwiftData-backed conformance lives in
/// `InterlinedPersistence`.
///
/// All methods are `async` so a real implementation can hop to a database
/// actor; they are non-throwing because a cache miss or write failure must
/// never break a live fetch — the service treats the cache as best-effort.
///
/// **Granularity.** The store is keyed by list id for everything except the
/// "all my lists" page, which is keyed implicitly under the same domain
/// (cacheLists / cachedLists). M3 ships only the writer's-own lists page;
/// when the M5+ shared-with-me view lands it should add its own keyed entry
/// point rather than mixing entries with the owned page.
public protocol ListsStore: Sendable {

    // MARK: - Lists

    /// The cached owned-list page, or `[]` when nothing is cached.
    func cachedLists() async -> [OwnedList]

    /// Replaces the cached owned-list page with a fresh slice. Each list is
    /// also indexed by id (so `cachedList(id:)` is consistent with whatever
    /// is in the page).
    func cacheLists(_ lists: [OwnedList]) async

    /// A single cached list by id, or `nil` when not cached.
    func cachedList(id: String) async -> OwnedList?

    /// Inserts or updates a single list in the by-id index. Used after a
    /// detail fetch or after a create / update / refresh response.
    func cacheList(_ list: OwnedList) async

    /// Removes a single list from every cached slice (by-id + owned page).
    /// Called after a successful `DELETE /api/lists/[id]`. Missing-id is a
    /// no-op.
    func removeList(id: String) async

    // MARK: - Rows

    /// Cached rows for a list, in stored order, or `[]` when nothing is
    /// cached.
    func cachedRows(of listId: String) async -> [ListRow]

    /// Replaces the cached rows for a list. Each row is indexed by id within
    /// its parent list — there is no global by-id row store yet.
    func cacheRows(_ rows: [ListRow], of listId: String) async

    // MARK: - Clear

    /// Drops every cached value. Called on sign-out.
    func clear() async
}
