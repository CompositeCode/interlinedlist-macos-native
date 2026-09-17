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

    /// When the change was queued. A human-facing timestamp — it is shown in
    /// sync UI and used for staleness decisions.
    ///
    /// - Important: **not** the sort key. See ``sequence``.
    var enqueuedAt: Date

    /// The queue position. Strictly increasing, assigned inside the same save
    /// that inserts the row.
    ///
    /// This exists because `enqueuedAt` is **not a total order** (GitHub #84).
    /// The outbox is a FIFO whose entire contract is *replay these changes in
    /// the order they happened*, and it was sorted by timestamp alone — two
    /// entries stamped in the same instant tie, and `SortDescriptor` specifies
    /// no tiebreak, so their relative order was whatever the store happened to
    /// return. For a document-sync queue that means an `.updateDocument`
    /// replayed before the `.createDocument` it depends on, or a
    /// `.deleteFolder` overtaking the `.renameFolder` ahead of it.
    ///
    /// The tests knew: three of them slept between enqueues, commented
    /// *"SwiftData uses Date() at enqueue — sleep briefly so timestamps
    /// differ."* A test that has to slow the system down to make its assertion
    /// true is describing a defect in the system.
    ///
    /// Derived from `max(sequence) + 1` **read from the store**, not from a
    /// process-local counter: a counter would restart at zero on the next
    /// launch and interleave new entries among old ones.
    ///
    /// Additive with a default, so SwiftData's lightweight migration opens an
    /// existing store. Rows written before this field arrive as `0` and
    /// therefore sort ahead of everything new — which is correct, because they
    /// *are* older. Their order relative to each other is whatever it already
    /// was; this change cannot retroactively recover an order that was never
    /// recorded.
    var sequence: Int = 0

    var attemptCount: Int
    var lastError: String?

    init(
        id: String = UUID().uuidString,
        kind: String,
        targetId: String,
        payloadJSON: Data,
        enqueuedAt: Date,
        sequence: Int = 0,
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetId = targetId
        self.payloadJSON = payloadJSON
        self.enqueuedAt = enqueuedAt
        self.sequence = sequence
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}
