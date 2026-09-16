import XCTest
import InterlinedDomain
@testable import InterlinedPersistence

/// BDD-named coverage for `SwiftDataDocumentStore` (Wave 5.1 / M4). Mirrors
/// `SwiftDataListsStoreTests`: round-trip, second-write-wins, folder cascade,
/// outbox enqueue/dequeue/order, sync-state read/write, and the no-op
/// `NullDocumentStore` boundary.
final class SwiftDataDocumentStoreTests: XCTestCase {

    // MARK: - Document round-trip

    func test_givenUpsertedDocument_whenReadingByID_thenRoundTripsAllFields() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let original = Document(
            id: "doc-1",
            folderId: "f-1",
            title: "Welcome",
            body: DocumentBody(markdown: "# Hello"),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPublic: true,
            deleted: false,
            version: "v1"
        )

        // When
        await store.upsert(original, localEditedAt: nil)

        // Then
        let fetched = await store.cachedDocument(id: "doc-1")
        XCTAssertEqual(fetched, original)
    }

    func test_givenSecondUpsert_whenReadingByID_thenSecondWriteWins() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(sampleDocument(id: "d", title: "v1"), localEditedAt: nil)

        // When
        await store.upsert(sampleDocument(id: "d", title: "v2"), localEditedAt: nil)

        // Then
        let fetched = await store.cachedDocument(id: "d")
        XCTAssertEqual(fetched?.title, "v2")
    }

    func test_givenEmptyStore_whenReadingDocument_thenReturnsNil() async throws {
        // Given — boundary.
        let store = try SwiftDataDocumentStore.inMemory()

        // When / Then
        let fetched = await store.cachedDocument(id: "missing")
        XCTAssertNil(fetched)
    }

    func test_givenDocumentWithLocalEdit_whenReadingLocalEditedAt_thenReturnsDate() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        await store.upsert(sampleDocument(id: "d"), localEditedAt: when)

        // When
        let edited = await store.localEditedAt(id: "d")

        // Then
        XCTAssertEqual(edited, when)
    }

    func test_givenClearLocalEdit_whenCalled_thenLocalEditedAtIsNil() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(sampleDocument(id: "d"), localEditedAt: Date())

        // When
        await store.clearLocalEdit(id: "d")

        // Then
        let edited = await store.localEditedAt(id: "d")
        XCTAssertNil(edited)
    }

    func test_givenRemoveDocument_whenCalled_thenDocumentDropped() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(sampleDocument(id: "d"), localEditedAt: nil)

        // When
        await store.removeDocument(id: "d")

        // Then
        let fetched = await store.cachedDocument(id: "d")
        XCTAssertNil(fetched)
    }

    // MARK: - Folder round-trip

    func test_givenUpsertedFolder_whenReadingByID_thenRoundTripsAllFields() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let folder = FolderNode(
            id: "f1",
            parentId: nil,
            name: "Archive",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            deleted: false
        )

        // When
        await store.upsertFolder(folder)

        // Then
        let fetched = await store.cachedFolder(id: "f1")
        XCTAssertEqual(fetched, folder)
    }

    func test_givenEmptyStore_whenReadingFolder_thenReturnsNil() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()

        // When / Then
        let fetched = await store.cachedFolder(id: "missing")
        XCTAssertNil(fetched)
    }

    func test_givenMultipleFolders_whenReadingAllFolders_thenReturnsEvery() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsertFolder(FolderNode(id: "a", name: "A"))
        await store.upsertFolder(FolderNode(id: "b", name: "B"))

        // When
        let all = await store.allFolders()

        // Then
        XCTAssertEqual(Set(all.map(\.id)), Set(["a", "b"]))
    }

    // MARK: - Folder cascade on remove

    func test_givenFolderWithDocuments_whenRemoved_thenDocumentsCascaded() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsertFolder(FolderNode(id: "f", name: "F"))
        await store.upsert(sampleDocument(id: "d1", folderId: "f"), localEditedAt: nil)
        await store.upsert(sampleDocument(id: "d2", folderId: "f"), localEditedAt: nil)
        await store.upsert(sampleDocument(id: "d3", folderId: nil), localEditedAt: nil) // root-level, kept

        // When
        await store.removeFolder(id: "f")

        // Then — folder and its documents are gone; root document survives.
        let folder = await store.cachedFolder(id: "f")
        let docs = await store.allDocuments()
        XCTAssertNil(folder)
        XCTAssertEqual(Set(docs.map(\.id)), Set(["d3"]))
    }

    func test_givenMissingFolderId_whenRemoved_thenNoOpAndNoCrash() async throws {
        // Given — boundary.
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsertFolder(FolderNode(id: "a", name: "A"))

        // When
        await store.removeFolder(id: "never-cached")

        // Then — kept.
        let folder = await store.cachedFolder(id: "a")
        XCTAssertNotNil(folder)
    }

    // MARK: - Outbox

    func test_givenOutboxEntries_whenReading_thenOrderedByEnqueuedAtAscending() async throws {
        // Given — enqueue three changes; expect FIFO order on read.
        // No sleeps. Three enqueues back to back is the regression test:
        // ordering used to depend on `Date()` resolution separating them, which
        // is why this test slept between each one (GitHub #84). The queue is
        // sorted by a monotonic `sequence` now, so same-instant enqueues keep
        // their order.
        let store = try SwiftDataDocumentStore.inMemory()
        try await store.enqueueOutbox(.deleteDocument(id: "first"))
        try await store.enqueueOutbox(.deleteDocument(id: "second"))
        try await store.enqueueOutbox(.deleteDocument(id: "third"))

        // When
        let entries = await store.outboxEntries()

        // Then
        XCTAssertEqual(entries.map { $0.change.targetId }, ["first", "second", "third"])
    }

    func test_givenEnqueuedChange_whenDequeued_thenRemoved() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        try await store.enqueueOutbox(.deleteDocument(id: "d-x"))
        let initial = await store.outboxEntries()
        let entryId = try XCTUnwrap(initial.first?.id)

        // When
        await store.dequeueOutbox(entryId: entryId)

        // Then
        let after = await store.outboxEntries()
        XCTAssertTrue(after.isEmpty)
    }

    func test_givenEmptyOutbox_whenReading_thenReturnsEmpty() async throws {
        // Given — boundary.
        let store = try SwiftDataDocumentStore.inMemory()

        // When / Then
        let entries = await store.outboxEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    func test_givenOutboxEntry_whenMarkedFailure_thenAttemptCountAndErrorRecorded() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        try await store.enqueueOutbox(.deleteDocument(id: "d"))
        let initial = await store.outboxEntries()
        let entryId = try XCTUnwrap(initial.first?.id)

        // When
        await store.markOutboxFailure(entryId: entryId, message: "transport error")

        // Then
        let after = await store.outboxEntries()
        XCTAssertEqual(after.first?.attemptCount, 1)
        XCTAssertEqual(after.first?.lastError, "transport error")
    }

    func test_givenOutboxAllChangeKinds_whenRoundTripped_thenPayloadDecodes() async throws {
        // Given — exhaustive enum round-trip.
        let store = try SwiftDataDocumentStore.inMemory()
        let changes: [DocumentChange] = [
            .createDocument(id: "d1", folderId: "f1", title: "T", body: "B", isPublic: true),
            .updateDocument(id: "d2", title: "U", body: nil, folderId: nil, isPublic: nil),
            .deleteDocument(id: "d3"),
            .createFolder(id: "f2", name: "F", parentId: nil),
            .renameFolder(id: "f3", name: "R", parentId: "f4"),
            .deleteFolder(id: "f5")
        ]
        // Six enqueues with no delay between them — the case the 2 ms sleep here
        // was papering over.
        for change in changes {
            try await store.enqueueOutbox(change)
        }

        // When
        let entries = await store.outboxEntries()

        // Then — every change decodes back to its original form.
        XCTAssertEqual(entries.map(\.change), changes)
    }

    // MARK: - Sync state

    func test_givenNoSyncState_whenReading_thenReturnsNil() async throws {
        // Given — boundary.
        let store = try SwiftDataDocumentStore.inMemory()

        // When / Then
        let at = await store.lastSyncAt()
        let token = await store.lastSyncToken()
        XCTAssertNil(at)
        XCTAssertNil(token)
    }

    func test_givenSyncState_whenUpdated_thenReadable() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let when = Date(timeIntervalSince1970: 1_800_000_000)

        // When
        await store.updateSyncState(lastSyncAt: when, lastSyncToken: "abc", pendingOutboxCount: 3)

        // Then
        let at = await store.lastSyncAt()
        let token = await store.lastSyncToken()
        XCTAssertEqual(at, when)
        XCTAssertEqual(token, "abc")
    }

    func test_givenSyncStateUpdatedTwice_whenReading_thenSecondWriteWins() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = Date(timeIntervalSince1970: 1_800_000_000)
        await store.updateSyncState(lastSyncAt: first, lastSyncToken: "x", pendingOutboxCount: 0)

        // When
        await store.updateSyncState(lastSyncAt: second, lastSyncToken: "y", pendingOutboxCount: 0)

        // Then
        let at = await store.lastSyncAt()
        XCTAssertEqual(at, second)
        let token = await store.lastSyncToken()
        XCTAssertEqual(token, "y")
    }

    // MARK: - Clear

    func test_givenPopulatedStore_whenCleared_thenEverythingEmpty() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(sampleDocument(id: "d"), localEditedAt: nil)
        await store.upsertFolder(FolderNode(id: "f", name: "F"))
        try await store.enqueueOutbox(.deleteDocument(id: "d"))
        await store.updateSyncState(lastSyncAt: Date(), lastSyncToken: nil, pendingOutboxCount: 1)

        // When
        await store.clear()

        // Then
        let docs = await store.allDocuments()
        let folders = await store.allFolders()
        let outbox = await store.outboxEntries()
        let at = await store.lastSyncAt()
        XCTAssertTrue(docs.isEmpty)
        XCTAssertTrue(folders.isEmpty)
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertNil(at)
    }

    // MARK: - NullDocumentStore

    func test_givenNullDocumentStore_whenCalledOnEveryMethod_thenNoOpAndEmpty() async throws {
        // Given — boundary: the no-op store used in hostile boot conditions.
        let store = NullDocumentStore()

        // When
        await store.upsert(sampleDocument(id: "d"), localEditedAt: nil)
        await store.upsertFolder(FolderNode(id: "f", name: "F"))
        try await store.enqueueOutbox(.deleteDocument(id: "d"))
        await store.updateSyncState(lastSyncAt: Date(), lastSyncToken: nil, pendingOutboxCount: 0)

        // Then — every read returns empty / nil.
        let docs = await store.allDocuments()
        let folders = await store.allFolders()
        let entries = await store.outboxEntries()
        let at = await store.lastSyncAt()
        XCTAssertTrue(docs.isEmpty)
        XCTAssertTrue(folders.isEmpty)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertNil(at)
    }

    // MARK: - Helpers

    private func sampleDocument(
        id: String,
        title: String = "Doc",
        folderId: String? = nil
    ) -> Document {
        Document(
            id: id,
            folderId: folderId,
            title: title,
            body: DocumentBody(markdown: "body"),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPublic: false,
            deleted: false,
            version: nil
        )
    }
}

// MARK: - Outbox FIFO ordering (GitHub #84)
//
// The outbox is a queue whose entire contract is "replay these in the order they
// happened", and it was ordered by `enqueuedAt` alone — a **non-total** key. Two
// entries stamped in the same instant tie, `SortDescriptor` specifies no
// tiebreak, and their relative order was whatever the store returned. For
// document sync that means an `.updateDocument` replayed before the
// `.createDocument` it depends on.
//
// These tests all enqueue with **no delay**, which is precisely what the old
// implementation could not survive.

extension SwiftDataDocumentStoreTests {

    // Happy path

    func test_givenManySameInstantEnqueues_whenReading_thenOrderIsExactlyInsertionOrder() async throws {
        // Fifty in a tight loop. Timestamp resolution cannot be relied on to
        // separate these, which is the whole point.
        let store = try SwiftDataDocumentStore.inMemory()
        let ids = (0..<50).map { "d\($0)" }
        for id in ids {
            try await store.enqueueOutbox(.deleteDocument(id: id))
        }

        let entries = await store.outboxEntries()

        XCTAssertEqual(entries.map { $0.change.targetId }, ids)
    }

    func test_givenEnqueuedEntries_whenReading_thenSequencesAreStrictlyIncreasing() async throws {
        // The property that makes the order total. Equal sequences would put the
        // tie right back.
        let store = try SwiftDataDocumentStore.inMemory()
        for id in ["a", "b", "c", "d"] {
            try await store.enqueueOutbox(.deleteDocument(id: id))
        }

        let entries = await store.outboxEntries()
        let targets = entries.map { $0.change.targetId }

        XCTAssertEqual(targets, ["a", "b", "c", "d"])
        XCTAssertEqual(Set(targets).count, targets.count, "no two entries collapsed onto one another")
    }

    // The case that would break a count-based sequence

    func test_givenADequeueFromTheMiddle_whenEnqueuingMore_thenTheNewEntriesStillSortLast() async throws {
        // Dequeuing removes rows, so a sequence derived from the row *count*
        // would reissue a position already held by an entry still waiting —
        // and two entries sharing a position is the original bug again.
        let store = try SwiftDataDocumentStore.inMemory()
        for id in ["a", "b", "c"] {
            try await store.enqueueOutbox(.deleteDocument(id: id))
        }
        let queued = await store.outboxEntries()
        let first = try XCTUnwrap(queued.first)
        await store.dequeueOutbox(entryId: first.id)

        try await store.enqueueOutbox(.deleteDocument(id: "d"))
        try await store.enqueueOutbox(.deleteDocument(id: "e"))

        let entries = await store.outboxEntries()
        XCTAssertEqual(entries.map { $0.change.targetId }, ["b", "c", "d", "e"])
    }

    func test_givenTheQueueFullyDrained_whenEnqueuingAgain_thenOrderStillHolds() async throws {
        // Boundary: an empty queue restarts from whatever position is free.
        // Order within the new batch is what matters, and it must not depend on
        // the store having been emptied or not.
        let store = try SwiftDataDocumentStore.inMemory()
        for id in ["a", "b"] {
            try await store.enqueueOutbox(.deleteDocument(id: id))
        }
        for entry in await store.outboxEntries() {
            await store.dequeueOutbox(entryId: entry.id)
        }
        let drained = await store.outboxEntries()
        XCTAssertTrue(drained.isEmpty)

        for id in ["c", "d", "e"] {
            try await store.enqueueOutbox(.deleteDocument(id: id))
        }

        let entries = await store.outboxEntries()
        XCTAssertEqual(entries.map { $0.change.targetId }, ["c", "d", "e"])
    }

    // Invalid input — an unreadable payload must not disturb the rest

    func test_givenAFailedPush_whenMarkedAndReRead_thenTheEntryKeepsItsPlace() async throws {
        // A retry must not send an entry to the back of the queue. The engine
        // keeps failed rows queued for the next cycle, and reordering them would
        // let a later change overtake the one that is blocking it.
        let store = try SwiftDataDocumentStore.inMemory()
        for id in ["a", "b", "c"] {
            try await store.enqueueOutbox(.deleteDocument(id: id))
        }
        let queued = await store.outboxEntries()
        let first = try XCTUnwrap(queued.first)

        await store.markOutboxFailure(entryId: first.id, message: "offline")

        let entries = await store.outboxEntries()
        XCTAssertEqual(entries.map { $0.change.targetId }, ["a", "b", "c"])
        XCTAssertEqual(entries.first?.attemptCount, 1)
    }

    // Dependency ordering — the failure this actually prevents

    func test_givenACreateThenUpdateOfTheSameDocument_whenReplayed_thenTheCreateComesFirst() async throws {
        // The concrete data-loss shape: an update replayed before the create it
        // depends on. Enqueued back to back, as the sync engine would.
        let store = try SwiftDataDocumentStore.inMemory()
        try await store.enqueueOutbox(
            .createDocument(id: "d1", folderId: nil, title: "T", body: "B", isPublic: false)
        )
        try await store.enqueueOutbox(
            .updateDocument(id: "d1", title: "T2", body: nil, folderId: nil, isPublic: nil)
        )

        let kinds = await store.outboxEntries().map { $0.change.kind }

        XCTAssertEqual(kinds, [.createDocument, .updateDocument])
    }
}

// MARK: - Lightweight migration of an existing on-disk store (GitHub #84)
//
// `sequence` is additive with a default, which is what lets SwiftData open a
// store written before it existed. Asserting that against a **real file** rather
// than an in-memory container is the point: in-memory containers are created
// fresh every time and can never exercise a migration.

extension SwiftDataDocumentStoreTests {

    func test_givenAnOnDiskStore_whenReopened_thenExistingEntriesSurviveAndStayOrdered() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("documents.store")

        // Write, then drop the store entirely so the reopen is a real reopen.
        do {
            let store = try SwiftDataDocumentStore.onDisk(at: url)
            for id in ["a", "b", "c"] {
                try await store.enqueueOutbox(.deleteDocument(id: id))
            }
            let written = await store.outboxEntries()
            XCTAssertEqual(written.count, 3)
        }

        let reopened = try SwiftDataDocumentStore.onDisk(at: url)
        let entries = await reopened.outboxEntries()

        XCTAssertEqual(entries.map { $0.change.targetId }, ["a", "b", "c"], "order survives a reopen")

        // And the sequence continues from where it left off rather than
        // restarting — which is exactly what a process-local counter would get
        // wrong, interleaving new entries among the old ones.
        try await reopened.enqueueOutbox(.deleteDocument(id: "d"))
        let after = await reopened.outboxEntries()
        XCTAssertEqual(after.map { $0.change.targetId }, ["a", "b", "c", "d"])
    }
}
