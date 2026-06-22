import Foundation
import SwiftData

/// SwiftData record for a cached timeline slice (PLAN.md §5).
///
/// Keyed by `(scopeRaw, tag)` — the same composite key the in-memory store
/// uses. Holds an ordered list of message ids so `cachedTimeline(scope:tag:)`
/// is a single keyed lookup that hydrates messages from `MessageRecord`s by
/// id. `fetchedAt` is recorded for future stale-while-revalidate policy
/// (not yet consumed by the M1 store).
///
/// Internal to the package.
@Model
final class TimelinePageRecord {
    /// `TimelineScope.rawScopeKey` — a stable string form of the enum case.
    /// Kept as a `String` rather than the enum itself because SwiftData
    /// macros on macOS 14 do not play well with non-Codable raw-value
    /// enums under strict concurrency.
    var scopeRaw: String
    /// Optional tag filter (`nil` means "no tag filter"). Combined with
    /// `scopeRaw` to identify a distinct cached feed.
    var tag: String?
    /// Ordered ids of the cached messages, in timeline order.
    var messageIDs: [String]
    /// When this slice was last replaced. Reserved for future
    /// stale-while-revalidate decisions.
    var fetchedAt: Date

    init(scopeRaw: String, tag: String?, messageIDs: [String], fetchedAt: Date) {
        self.scopeRaw = scopeRaw
        self.tag = tag
        self.messageIDs = messageIDs
        self.fetchedAt = fetchedAt
    }
}
