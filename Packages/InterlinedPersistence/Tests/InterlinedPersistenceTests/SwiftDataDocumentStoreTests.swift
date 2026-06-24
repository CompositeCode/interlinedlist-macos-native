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
        let store = try SwiftDataDocumentStore.inMemory()
        try await store.enqueueOutbox(.deleteDocument(id: "first"))
        // SwiftData uses Date() at enqueue — sleep briefly so timestamps differ.
        try await Task.sleep(nanoseconds: 5_000_000)
        try await store.enqueueOutbox(.deleteDocument(id: "second"))
        try await Task.sleep(nanoseconds: 5_000_000)
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
        for change in changes {
            try await store.enqueueOutbox(change)
            try await Task.sleep(nanoseconds: 2_000_000)
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
