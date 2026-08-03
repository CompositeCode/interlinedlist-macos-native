import Foundation

/// The organizations cache port (PLAN.md §5 — stale-while-revalidate). Mirrors
/// `ListsStore` / `MessageStore`: the domain layer exposes the protocol; the
/// SwiftData-backed conformance lives in `InterlinedPersistence`.
///
/// Scope is the **caller's own memberships** — the initial-view data the
/// Organizations sidebar / switcher paints from. Each cached value is a
/// `UserOrganization` (the org fields + the caller's role + joined-at), stored
/// in the order the API returned them so the switcher renders identically
/// online and offline.
///
/// All methods are `async` so a real implementation can hop to a database
/// actor; they are non-throwing because a cache miss or write failure must
/// never break a live fetch — the service treats the cache as best-effort.
public protocol OrgStore: Sendable {

    /// The cached membership list, in stored order, or `[]` when nothing is
    /// cached.
    func cachedMemberships() async -> [UserOrganization]

    /// Replaces the cached membership set with a fresh slice (page semantics:
    /// a new call fully supersedes the previous one, so an org the caller left
    /// disappears from the cache). Stored order matches the passed order.
    func cacheMemberships(_ memberships: [UserOrganization]) async

    /// Drops every cached membership. Called on sign-out.
    func clear() async
}
