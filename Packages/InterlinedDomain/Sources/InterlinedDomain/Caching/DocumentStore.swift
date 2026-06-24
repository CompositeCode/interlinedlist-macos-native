import Foundation

/// The documents cache port (PLAN.md §3 — "DocumentSyncEngine queues local
/// edits for batch POST" and "Documents fully offline-capable via the sync
/// engine"). The SwiftData-backed conformance lives in
/// `InterlinedPersistence`; the domain layer exposes only this protocol so
/// the engine and the service can be tested without a database.
///
/// All methods are `async` so a real implementation can hop to a database
/// actor; most are non-throwing because the cache is best-effort. The
/// outbox / sync-state methods *do* throw — the engine cares whether the
/// queue and the cursor were durably written.
public protocol DocumentStore: Sendable {

    // MARK: - Documents

    /// Every cached document, including tombstoned rows (the engine needs
    /// them to debounce repeated delete deltas).
    func allDocuments() async -> [Document]

    /// One cached document by id, or `nil`. The engine uses this to detect
    /// "did we already have this row" without scanning `allDocuments`.
    func cachedDocument(id: String) async -> Document?

    /// The local-edit dirty flag. `nil` when the document is in sync, the
    /// timestamp of the last local edit otherwise. Carried separately from
    /// `Document` because the dirty flag is a persistence-only concern.
    func localEditedAt(id: String) async -> Date?

    /// Insert or update a document. When `localEditedAt` is `nil`, the
    /// engine is folding in a server delta; otherwise the caller is the
    /// service marking a local edit.
    func upsert(_ document: Document, localEditedAt: Date?) async

    /// Remove a document hard (used by the engine after a successful push
    /// of a `deleteDocument` change, and by the cascade in `deleteFolder`).
    func removeDocument(id: String) async

    /// Mark a document clean (called by the engine after a successful
    /// `update` push). No-op when the id isn't cached.
    func clearLocalEdit(id: String) async

    // MARK: - Folders

    func allFolders() async -> [FolderNode]
    func cachedFolder(id: String) async -> FolderNode?
    func upsertFolder(_ folder: FolderNode) async
    /// Hard-removes a folder. Cascades to every document with
    /// `folderId == id`.
    func removeFolder(id: String) async

    // MARK: - Outbox

    /// Append a change to the outbox.
    func enqueueOutbox(_ change: DocumentChange) async throws

    /// Every outbox entry, ordered by `enqueuedAt` ascending.
    func outboxEntries() async -> [OutboxEntry]

    /// Drop an outbox entry by row id (the entry's own primary key, not
    /// the document's). Called after a successful push.
    func dequeueOutbox(entryId: String) async

    /// Record a failed-push outcome on an outbox row: bump `attemptCount`,
    /// store `lastError`. The row stays in the outbox.
    func markOutboxFailure(entryId: String, message: String) async

    // MARK: - Sync state

    /// The `lastSyncAt` cursor (the next pull's `since` parameter).
    func lastSyncAt() async -> Date?

    /// The opaque token, if the API uses one. Stored alongside `lastSyncAt`
    /// so adoption is a single write.
    func lastSyncToken() async -> String?

    /// Update the sync state. Called by the engine at the end of every
    /// cycle.
    func updateSyncState(lastSyncAt: Date?, lastSyncToken: String?, pendingOutboxCount: Int) async

    // MARK: - Clear

    /// Drop every cached value. Called on sign-out.
    func clear() async
}

// MARK: - OutboxEntry

/// One queued outbox row, projected for engine consumption. Mirrors
/// `OutboxEntryRecord` (which is internal to the persistence package) so
/// the engine consumes a value-typed snapshot and the SwiftData `@Model`
/// never escapes the store.
public struct OutboxEntry: Sendable, Equatable, Identifiable {

    public let id: String
    public let change: DocumentChange
    public let enqueuedAt: Date
    public let attemptCount: Int
    public let lastError: String?

    public init(
        id: String,
        change: DocumentChange,
        enqueuedAt: Date,
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.change = change
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}
