import Foundation

/// The cache port the persistence layer implements (PLAN.md §5 — timeline and
/// lists read from a SwiftData cache with stale-while-revalidate). The
/// SwiftData-backed conformance lives in `InterlinedPersistence`; the domain
/// layer depends only on this protocol so its services can be tested without a
/// database and run cache-less when no store is injected.
///
/// All methods are `async` so a real implementation can hop to a database
/// actor; they are non-throwing because a cache miss or write failure must
/// never break a live fetch — the service treats the cache as best-effort.
public protocol MessageStore: Sendable {
    /// The cached messages for a given timeline scope + tag filter, or `[]`
    /// when nothing is cached.
    func cachedTimeline(scope: TimelineScope, tag: String?) async -> [Message]

    /// Replaces the cached messages for a scope + tag with a fresh page.
    func replaceTimeline(_ messages: [Message], scope: TimelineScope, tag: String?) async

    /// A single cached message by id, or `nil` when not cached.
    func cachedMessage(id: String) async -> Message?

    /// Inserts or updates messages in the by-id cache.
    func upsert(_ messages: [Message]) async

    /// Clears all cached state. Called on sign-out.
    func clear() async
}
