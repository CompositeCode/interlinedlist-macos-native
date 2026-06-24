import Foundation
import os
import InterlinedDomain
import InterlinedKit

/// The single owner of `/api/documents/sync` (PLAN.md §3, §6 M4).
///
/// One cycle of `syncNow()` does, in order:
///
/// 1. **Pull delta** — `transport.pullDelta(since: lastSyncAt)`.
/// 2. **Apply delta** — for each remote document/folder:
///    - absent locally → insert (no event beyond the batched `deltaApplied`).
///    - present locally, clean (`localEditedAt == nil`) → overwrite with server.
///    - present locally, dirty, server `updatedAt > localEditedAt` → CONFLICT:
///      preserve the local copy as a new document titled "<original> (local
///      copy)" and apply the server version to the original id. Emits
///      `conflictResolved(original:, preservedAs:)`.
///    - present locally, dirty, server `updatedAt <= localEditedAt` → keep
///      local dirty; the outbox push will reconcile.
///    - `deleted == true` → remove locally (cascade to folder membership for
///      folders).
/// 3. **Emit `deltaApplied`** with the partitioned id sets.
/// 4. **Push outbox** — translate each `OutboxEntry` to a `DocumentChange`
///    and call `transport.pushChange(_:)`. On success: drop the row + clear
///    the `localEditedAt` for the affected document. On per-row failure:
///    bump `attemptCount` + store `lastError`; the row stays queued.
/// 5. **Update `lastSyncAt`** to the server's reported `syncedAt` (or the
///    engine clock if the API omitted it).
/// 6. **Emit `pushed`** for the successfully pushed document ids.
///
/// Errors: any failure during the *pull* aborts the cycle and re-throws as
/// `DocumentsError.syncFailed` — no partial-delta state is committed.
/// Per-push errors stay local: failed rows count as failures, successful
/// pushes still commit.
///
/// The engine takes `DocumentSyncTransport` (domain) rather than the kit
/// client directly so the persistence package can stay Kit-free.
public actor DocumentSyncEngine: DocumentSyncCoordinating {

    // MARK: - Stored state

    private let transport: DocumentSyncTransport
    private let store: DocumentStore
    private let clock: @Sendable () -> Date
    private let logger = Logger(
        subsystem: "com.interlinedlist.macos.persistence",
        category: "DocumentSyncEngine"
    )

    /// Event-stream continuation, captured at init. Stays alive for the
    /// engine's lifetime; consumers can drop the iterator without breaking
    /// downstream subscribers.
    private let eventContinuation: AsyncStream<DocumentSyncEvent>.Continuation
    /// The actual public stream. Re-used across multiple subscribers via
    /// `AsyncStream.makeStream`'s buffered behaviour.
    public nonisolated let events: AsyncStream<DocumentSyncEvent>

    // MARK: - Init

    public init(
        transport: DocumentSyncTransport,
        store: DocumentStore,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.store = store
        self.clock = clock
        let (stream, continuation) = AsyncStream<DocumentSyncEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.events = stream
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    // MARK: - DocumentSyncCoordinating

    public func enqueue(_ change: DocumentChange) async {
        do {
            try await store.enqueueOutbox(change)
        } catch {
            logger.error("Failed to enqueue outbox entry: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func syncNow() async throws -> DocumentSyncReport {
        // 1. Pull delta. Any error here aborts the cycle — no partial state.
        let since = await store.lastSyncAt()
        let pullResponse: DocumentSyncDelta
        do {
            pullResponse = try await transport.pullDelta(since: since)
        } catch let error as DocumentsError {
            throw error
        } catch let error as APIError {
            throw DocumentsError.syncFailed(underlying: error)
        } catch {
            throw DocumentsError.syncFailed(
                underlying: .transport(message: error.localizedDescription)
            )
        }

        // 2. Apply delta.
        let applyResult = await applyDelta(pullResponse)

        // 3. Emit conflict events first, then the batched delta event.
        for conflict in applyResult.conflicts {
            eventContinuation.yield(
                .conflictResolved(original: conflict.original, preservedAs: conflict.preservedAs)
            )
        }
        eventContinuation.yield(
            .deltaApplied(
                insertedIds: applyResult.insertedDocumentIds,
                updatedIds: applyResult.updatedDocumentIds,
                deletedIds: applyResult.deletedDocumentIds
            )
        )

        // 4. Push outbox.
        let pushResult = await pushOutbox()

        // 5. Update lastSyncAt.
        let nextCursor = pullResponse.syncedAt ?? clock()
        let pending = await store.outboxEntries().count
        await store.updateSyncState(
            lastSyncAt: nextCursor,
            lastSyncToken: nil, // API uses lastSyncAt directly today
            pendingOutboxCount: pending
        )

        // 6. Emit pushed.
        if !pushResult.pushedDocumentIds.isEmpty {
            eventContinuation.yield(.pushed(documentIds: pushResult.pushedDocumentIds))
        }

        return DocumentSyncReport(
            insertedDocumentIds: applyResult.insertedDocumentIds,
            updatedDocumentIds: applyResult.updatedDocumentIds,
            deletedDocumentIds: applyResult.deletedDocumentIds,
            insertedFolderIds: applyResult.insertedFolderIds,
            updatedFolderIds: applyResult.updatedFolderIds,
            deletedFolderIds: applyResult.deletedFolderIds,
            conflicts: applyResult.conflicts,
            pushedDocumentIds: pushResult.pushedDocumentIds,
            failedOutboxEntries: pushResult.failedEntries,
            lastSyncAt: nextCursor
        )
    }

    // MARK: - Delta application

    /// Internal struct holding partitioned id sets for the report + event.
    private struct ApplyResult {
        var insertedDocumentIds: [String] = []
        var updatedDocumentIds: [String] = []
        var deletedDocumentIds: [String] = []
        var insertedFolderIds: [String] = []
        var updatedFolderIds: [String] = []
        var deletedFolderIds: [String] = []
        var conflicts: [DocumentSyncReport.Conflict] = []
    }

    private func applyDelta(_ delta: DocumentSyncDelta) async -> ApplyResult {
        var result = ApplyResult()

        // Folders first so a document with a freshly-arrived folderId can
        // resolve. The wire-shape doesn't require this — folders are stored
        // independently — but it keeps the on-disk state internally
        // consistent at every intermediate save.
        for folder in delta.folders {
            let existing = await store.cachedFolder(id: folder.id)
            if folder.deleted {
                if existing != nil {
                    await store.removeFolder(id: folder.id)
                    result.deletedFolderIds.append(folder.id)
                }
                continue
            }
            await store.upsertFolder(folder)
            if existing == nil {
                result.insertedFolderIds.append(folder.id)
            } else {
                result.updatedFolderIds.append(folder.id)
            }
        }

        for document in delta.documents {
            let existing = await store.cachedDocument(id: document.id)
            let localEdit = await store.localEditedAt(id: document.id)

            // Tombstone — always wins, regardless of dirty.
            if document.deleted {
                if existing != nil {
                    await store.removeDocument(id: document.id)
                    result.deletedDocumentIds.append(document.id)
                }
                continue
            }

            // Absent locally → straight insert.
            guard existing != nil else {
                await store.upsert(document, localEditedAt: nil)
                result.insertedDocumentIds.append(document.id)
                continue
            }

            // Present + clean → overwrite.
            guard let localEdit else {
                await store.upsert(document, localEditedAt: nil)
                result.updatedDocumentIds.append(document.id)
                continue
            }

            // Present + dirty.
            if document.updatedAt > localEdit {
                // Conflict — preserve local, apply server.
                let preservedId = "\(document.id)-localcopy-\(UUID().uuidString)"
                let preserved = Document(
                    id: preservedId,
                    folderId: existing?.folderId,
                    title: (existing?.title ?? document.title) + " (local copy)",
                    body: existing?.body ?? DocumentBody.empty,
                    updatedAt: clock(),
                    createdAt: clock(),
                    isPublic: existing?.isPublic ?? false,
                    deleted: false,
                    version: nil
                )
                await store.upsert(preserved, localEditedAt: clock())
                await store.upsert(document, localEditedAt: nil)
                result.updatedDocumentIds.append(document.id)
                result.insertedDocumentIds.append(preservedId)
                result.conflicts.append(.init(original: document.id, preservedAs: preservedId))
            } else {
                // Local is newer or tied — keep dirty for push.
                // No store mutation, no result.append — the outbox push will
                // handle it.
            }
        }

        return result
    }

    // MARK: - Outbox push

    private struct PushResult {
        var pushedDocumentIds: [String] = []
        var failedEntries: [DocumentSyncReport.FailedOutboxEntry] = []
    }

    private func pushOutbox() async -> PushResult {
        var result = PushResult()
        let entries = await store.outboxEntries()
        for entry in entries {
            do {
                try await transport.pushChange(entry.change)
                await store.dequeueOutbox(entryId: entry.id)
                // Clear the dirty bit for affected documents so the next
                // pull doesn't see them as conflicting.
                switch entry.change {
                case .createDocument(let id, _, _, _, _),
                     .updateDocument(let id, _, _, _, _):
                    await store.clearLocalEdit(id: id)
                    result.pushedDocumentIds.append(id)
                case .deleteDocument(let id):
                    // Already gone locally if the caller did the deferred
                    // delete; the push only confirms it server-side.
                    result.pushedDocumentIds.append(id)
                case .createFolder, .renameFolder, .deleteFolder:
                    // Folder pushes don't surface a `pushed(documentIds:)`
                    // entry — the event is about documents.
                    break
                }
            } catch {
                let message = error.localizedDescription
                await store.markOutboxFailure(entryId: entry.id, message: message)
                result.failedEntries.append(
                    DocumentSyncReport.FailedOutboxEntry(
                        targetId: entry.change.targetId,
                        kind: entry.change.kind,
                        message: message
                    )
                )
            }
        }
        return result
    }
}

