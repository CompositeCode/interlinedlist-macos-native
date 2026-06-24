import Foundation
import SwiftData

/// Singleton row tracking the engine's sync state. Keyed by a constant
/// `pageKey` so SwiftData's lack of true singletons doesn't bite us — the
/// store fetches by that key, upserts, and never inserts a second row.
@Model
final class SyncStateRecord {

    /// Stable singleton key — always `"document-sync"`.
    @Attribute(.unique) var pageKey: String

    /// The `syncedAt` echoed by the last successful pull, or the engine
    /// clock when the API omitted it. Used as the next `since` parameter.
    var lastSyncAt: Date?

    /// Server-supplied sync cursor token. The current API uses `lastSyncAt`
    /// (ISO 8601 string) rather than an opaque token; this field is here so
    /// the engine can adopt a token without a schema migration if the API
    /// evolves.
    var lastSyncToken: String?

    /// Cached size of the outbox at the end of the last cycle. Surfaced to
    /// the UI as a status-bar indicator.
    var pendingOutboxCount: Int

    init(
        pageKey: String = "document-sync",
        lastSyncAt: Date? = nil,
        lastSyncToken: String? = nil,
        pendingOutboxCount: Int = 0
    ) {
        self.pageKey = pageKey
        self.lastSyncAt = lastSyncAt
        self.lastSyncToken = lastSyncToken
        self.pendingOutboxCount = pendingOutboxCount
    }
}
