import Foundation
import SwiftData

/// SwiftData record for one queued local change (PLAN.md §3 — "DocumentSyncEngine
/// queues local edits for batch POST"). One row per pending `DocumentChange`.
///
/// The payload is JSON-encoded so the row stays a flat scalar set even as
/// `DocumentChange` grows new associated values. The engine decodes the
/// payload on demand during `pushOutbox()`.
///
/// `attemptCount` and `lastError` are written when a push fails; the engine
/// keeps the row queued for the next cycle so transient failures self-heal.
@Model
final class OutboxEntryRecord {

    @Attribute(.unique) var id: String

    /// One of `DocumentChange.Kind.rawValue`. Stored as a string so the
    /// schema doesn't need an enum migration when the kind set grows.
    var kind: String

    /// The id of the document or folder this change targets. Indexed at
    /// query time so the engine can dedupe per-id when needed.
    var targetId: String

    /// JSON-encoded `DocumentChange`. Decoded by `DocumentChangeCodec`.
    var payloadJSON: Data

    var enqueuedAt: Date
    var attemptCount: Int
    var lastError: String?

    init(
        id: String = UUID().uuidString,
        kind: String,
        targetId: String,
        payloadJSON: Data,
        enqueuedAt: Date,
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetId = targetId
        self.payloadJSON = payloadJSON
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}
