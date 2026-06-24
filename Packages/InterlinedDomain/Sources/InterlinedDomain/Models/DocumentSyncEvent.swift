import Foundation

// MARK: - DocumentSyncEvent

/// Events the `DocumentSyncEngine` (lives in `InterlinedPersistence`) emits to
/// subscribers via its public `events: AsyncStream<DocumentSyncEvent>`.
///
/// The App layer drives in-app banners (conflict resolved → render
/// "Your local copy was preserved as …" inline) and refresh signals
/// (delta applied → list view rebinds; pushed → optimistic-edit chrome can
/// drop). Mirrors the pattern from the cross-window event bus referenced in
/// the M2 brief but is owned by the sync engine, not the composition root.
///
/// Ordering contract (asserted in `DocumentSyncEngineTests`): within one
/// `syncNow()` cycle, every `conflictResolved` event is emitted *before* the
/// batched `deltaApplied`, and `pushed` (if any) is emitted *after*
/// `deltaApplied`. The App layer can rely on this order to render the
/// "conflict was resolved" banner before the rebound list view scrolls past
/// the affected row.
public enum DocumentSyncEvent: Sendable, Equatable {

    /// Emitted once per `syncNow()` after the delta is folded into the local
    /// store. Carries the partitioned id sets so the App layer can rebind
    /// affected views without re-fetching.
    case deltaApplied(
        insertedIds: [Document.ID],
        updatedIds: [Document.ID],
        deletedIds: [Document.ID]
    )

    /// Emitted once per conflict resolution: the server version was applied
    /// to `original` and the local copy was preserved as `preservedAs`
    /// (a new document with title "<original-title> (local copy)"). The
    /// App layer surfaces this as an inline banner pointing at the
    /// preserved copy.
    case conflictResolved(original: Document.ID, preservedAs: Document.ID)

    /// Emitted once per `syncNow()` after the outbox push completes,
    /// carrying the document ids whose pending local edits were
    /// accepted by the server.
    case pushed(documentIds: [Document.ID])
}
