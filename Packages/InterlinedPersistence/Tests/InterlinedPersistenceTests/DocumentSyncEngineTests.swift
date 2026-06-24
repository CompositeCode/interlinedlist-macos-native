import XCTest
import InterlinedDomain
import InterlinedKit
@testable import InterlinedPersistence

/// BDD-named, property-style coverage for `DocumentSyncEngine` (Wave 5.1 /
/// M4, the deepest test surface in the project per PLAN.md §7). Simulated
/// delta sequences feed a stub transport; assertions cover insertions,
/// updates, deletes, conflicts, outbox push (success / partial / full
/// failure), monotonic cursor advancement, and AsyncStream event ordering.
final class DocumentSyncEngineTests: XCTestCase {

    // MARK: - Clock helper

    private final class FixedClock: @unchecked Sendable {
        private var current: Date
        init(start: Date) { self.current = start }
        func now() -> Date { current }
        func advance(by interval: TimeInterval) {
            current = current.addingTimeInterval(interval)
        }
    }

    // MARK: - Empty / no-op

    func test_givenEmptyDeltaAndEmptyLocalAndEmptyOutbox_whenSyncing_thenEmptyReport() async throws {
        // Given
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(syncedAt: nil))
        let store = try SwiftDataDocumentStore.inMemory()
        let engine = DocumentSyncEngine(transport: transport, store: store, clock: { Date(timeIntervalSince1970: 1_800_000_000) })

        // When
        let report = try await engine.syncNow()

        // Then
        XCTAssertTrue(report.insertedDocumentIds.isEmpty)
        XCTAssertTrue(report.updatedDocumentIds.isEmpty)
        XCTAssertTrue(report.deletedDocumentIds.isEmpty)
        XCTAssertTrue(report.conflicts.isEmpty)
        XCTAssertTrue(report.pushedDocumentIds.isEmpty)
    }

    // MARK: - Insert-only

    func test_givenInsertOnlyDelta_whenSyncing_thenDocumentsInsertedAndIdsReported() async throws {
        // Given
        let transport = StubSyncTransport()
        let delta = DocumentSyncDelta(
            syncedAt: nil,
            folders: [FolderNode(id: "f1", name: "F")],
            documents: [
                makeDocument(id: "d1", title: "A"),
                makeDocument(id: "d2", title: "B")
            ]
        )
        await transport.enqueuePull(delta)
        let store = try SwiftDataDocumentStore.inMemory()
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then
        XCTAssertEqual(Set(report.insertedDocumentIds), Set(["d1", "d2"]))
        XCTAssertEqual(report.insertedFolderIds, ["f1"])
        let cached = await store.allDocuments().map(\.id)
        XCTAssertEqual(Set(cached), Set(["d1", "d2"]))
    }

    // MARK: - Update-only (clean local)

    func test_givenUpdateOnlyDelta_whenLocalIsClean_thenLocalOverwrittenWithServer() async throws {
        // Given a clean local document; server delivers a newer version.
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(makeDocument(id: "d", title: "old"), localEditedAt: nil)
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(
            documents: [makeDocument(id: "d", title: "fresh", updatedAt: .distantFuture)]
        ))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then — server version applied; reported as updated.
        XCTAssertEqual(report.updatedDocumentIds, ["d"])
        let cached = await store.cachedDocument(id: "d")
        XCTAssertEqual(cached?.title, "fresh")
    }

    // MARK: - Delete-only

    func test_givenDeleteOnlyDelta_whenSyncing_thenDocumentRemovedAndIdReported() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(makeDocument(id: "d", title: "x"), localEditedAt: nil)
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(
            documents: [makeDocument(id: "d", title: "x", deleted: true)]
        ))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then
        XCTAssertEqual(report.deletedDocumentIds, ["d"])
        let cached = await store.cachedDocument(id: "d")
        XCTAssertNil(cached)
    }

    func test_givenDeleteOfMissingDocument_whenSyncing_thenIgnoredSilently() async throws {
        // Given — boundary: delete tombstone for a document we never cached.
        let store = try SwiftDataDocumentStore.inMemory()
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(
            documents: [makeDocument(id: "ghost", deleted: true)]
        ))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then — no spurious "deleted" id reported.
        XCTAssertTrue(report.deletedDocumentIds.isEmpty)
    }

    // MARK: - Mixed delta

    func test_givenMixedDelta_whenSyncing_thenAllIdsAreCorrectlyPartitioned() async throws {
        // Given — insert, update (clean), delete.
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(makeDocument(id: "to-update", title: "old"), localEditedAt: nil)
        await store.upsert(makeDocument(id: "to-delete", title: "x"), localEditedAt: nil)
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(documents: [
            makeDocument(id: "to-insert", title: "fresh"),
            makeDocument(id: "to-update", title: "newer", updatedAt: .distantFuture),
            makeDocument(id: "to-delete", deleted: true)
        ]))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then
        XCTAssertEqual(report.insertedDocumentIds, ["to-insert"])
        XCTAssertEqual(report.updatedDocumentIds, ["to-update"])
        XCTAssertEqual(report.deletedDocumentIds, ["to-delete"])
    }

    // MARK: - Conflict resolution

    func test_givenDirtyLocalAndStaleServer_whenSyncing_thenLocalRemainsDirtyAndNoConflict() async throws {
        // Given — local edited at T+10; server reports updatedAt T+5 → no conflict.
        let store = try SwiftDataDocumentStore.inMemory()
        let local = makeDocument(id: "d", title: "local", updatedAt: dateAt(0))
        await store.upsert(local, localEditedAt: dateAt(10))
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(documents: [
            makeDocument(id: "d", title: "server-stale", updatedAt: dateAt(5))
        ]))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then — no conflict, no update event; dirty bit preserved.
        XCTAssertTrue(report.conflicts.isEmpty)
        XCTAssertTrue(report.updatedDocumentIds.isEmpty)
        let cached = await store.cachedDocument(id: "d")
        XCTAssertEqual(cached?.title, "local")
        let localEdit = await store.localEditedAt(id: "d")
        XCTAssertEqual(localEdit, dateAt(10))
    }

    func test_givenDirtyLocalAndNewerServer_whenSyncing_thenConflictResolvedWithLocalCopyPreserved() async throws {
        // Given — local edited at T+5; server reports updatedAt T+10 → conflict.
        let store = try SwiftDataDocumentStore.inMemory()
        let local = makeDocument(id: "d", title: "local-title", updatedAt: dateAt(0))
        await store.upsert(local, localEditedAt: dateAt(5))
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(documents: [
            makeDocument(id: "d", title: "server-title", updatedAt: dateAt(10))
        ]))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then — original id holds server, preserved copy holds local body.
        XCTAssertEqual(report.conflicts.count, 1)
        let conflict = try XCTUnwrap(report.conflicts.first)
        XCTAssertEqual(conflict.original, "d")
        let server = await store.cachedDocument(id: "d")
        XCTAssertEqual(server?.title, "server-title")
        let preserved = await store.cachedDocument(id: conflict.preservedAs)
        XCTAssertEqual(preserved?.title, "local-title (local copy)")
    }

    func test_givenMultipleConflicts_whenSyncingOneCycle_thenAllResolved() async throws {
        // Given — two dirty docs both made newer on the server.
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(makeDocument(id: "d1", title: "l1", updatedAt: dateAt(0)), localEditedAt: dateAt(5))
        await store.upsert(makeDocument(id: "d2", title: "l2", updatedAt: dateAt(0)), localEditedAt: dateAt(5))
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(documents: [
            makeDocument(id: "d1", title: "s1", updatedAt: dateAt(10)),
            makeDocument(id: "d2", title: "s2", updatedAt: dateAt(10))
        ]))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then
        XCTAssertEqual(report.conflicts.count, 2)
        XCTAssertEqual(Set(report.conflicts.map(\.original)), Set(["d1", "d2"]))
    }

    // MARK: - Outbox push: happy

    func test_givenOutboxWithUpdate_whenSyncing_thenPushedAndDequeued() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let change = DocumentChange.updateDocument(id: "d", title: "x", body: "y", folderId: nil, isPublic: nil)
        try await store.enqueueOutbox(change)
        await store.upsert(makeDocument(id: "d", title: "local"), localEditedAt: Date())
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta())
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then — push happened, outbox empty, dirty bit cleared.
        XCTAssertEqual(report.pushedDocumentIds, ["d"])
        let remaining = await store.outboxEntries()
        XCTAssertTrue(remaining.isEmpty)
        let dirty = await store.localEditedAt(id: "d")
        XCTAssertNil(dirty)
    }

    func test_givenOutboxWithMultipleChanges_whenSyncing_thenAllPushedInOrder() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        try await store.enqueueOutbox(.updateDocument(id: "a", title: "1", body: nil, folderId: nil, isPublic: nil))
        try await Task.sleep(nanoseconds: 5_000_000)
        try await store.enqueueOutbox(.updateDocument(id: "b", title: "2", body: nil, folderId: nil, isPublic: nil))
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta())
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then
        XCTAssertEqual(report.pushedDocumentIds, ["a", "b"])
        let pushed = await transport.pushedChanges
        XCTAssertEqual(pushed.map { $0.targetId }, ["a", "b"])
    }

    // MARK: - Outbox push: partial failure

    func test_givenOutboxAndPartialPushFailure_whenSyncing_thenFailingRowStaysAndOthersSucceed() async throws {
        // Given — three changes; the middle one fails.
        let store = try SwiftDataDocumentStore.inMemory()
        try await store.enqueueOutbox(.deleteDocument(id: "first"))
        try await Task.sleep(nanoseconds: 5_000_000)
        try await store.enqueueOutbox(.deleteDocument(id: "second"))
        try await Task.sleep(nanoseconds: 5_000_000)
        try await store.enqueueOutbox(.deleteDocument(id: "third"))
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta())
        await transport.enqueuePushOutcome(.success)
        await transport.enqueuePushOutcome(.failure(.forbidden(serverMessage: "nope")))
        await transport.enqueuePushOutcome(.success)
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let report = try await engine.syncNow()

        // Then — first + third pushed; second failed and stayed queued.
        XCTAssertEqual(Set(report.pushedDocumentIds), Set(["first", "third"]))
        XCTAssertEqual(report.failedOutboxEntries.count, 1)
        XCTAssertEqual(report.failedOutboxEntries.first?.targetId, "second")
        let remaining = await store.outboxEntries()
        XCTAssertEqual(remaining.map { $0.change.targetId }, ["second"])
        XCTAssertEqual(remaining.first?.attemptCount, 1)
        XCTAssertNotNil(remaining.first?.lastError)
    }

    // MARK: - Pull failure (full cycle aborts)

    func test_givenPullFailure_whenSyncing_thenThrowsAndNoStateMutation() async throws {
        // Given — initial state present.
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(makeDocument(id: "d", title: "kept"), localEditedAt: nil)
        let transport = StubSyncTransport()
        await transport.enqueuePullFailure(.transport(message: "offline"))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When / Then
        do {
            _ = try await engine.syncNow()
            XCTFail("Expected DocumentsError.syncFailed")
        } catch let error as DocumentsError {
            if case .syncFailed(let underlying) = error {
                XCTAssertEqual(underlying, .transport(message: "offline"))
            } else {
                XCTFail("Expected .syncFailed, got \(error)")
            }
        }
        // State is preserved untouched.
        let kept = await store.cachedDocument(id: "d")
        XCTAssertEqual(kept?.title, "kept")
    }

    // MARK: - Monotonic lastSyncAt

    func test_givenRepeatedSyncs_whenServerSuppliesSyncedAt_thenCursorAdvances() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(syncedAt: dateAt(5)))
        await transport.enqueuePull(DocumentSyncDelta(syncedAt: dateAt(10)))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        let first = try await engine.syncNow()
        let second = try await engine.syncNow()

        // Then
        XCTAssertEqual(first.lastSyncAt, dateAt(5))
        XCTAssertEqual(second.lastSyncAt, dateAt(10))
        let cursor = await store.lastSyncAt()
        XCTAssertEqual(cursor, dateAt(10))
    }

    func test_givenSecondSync_whenPulled_thenSinceParameterIsFirstSyncCursor() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(syncedAt: dateAt(5)))
        await transport.enqueuePull(DocumentSyncDelta(syncedAt: dateAt(10)))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        _ = try await engine.syncNow()
        _ = try await engine.syncNow()

        // Then — first pull had since=nil; second pull had since=dateAt(5).
        let calls = await transport.pullCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertNil(calls.first ?? nil)
        XCTAssertEqual(calls.last ?? nil, dateAt(5))
    }

    func test_givenAPIOmitsSyncedAt_whenSyncing_thenFallsBackToInjectedClock() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(syncedAt: nil))
        let fixed = dateAt(42)
        let engine = DocumentSyncEngine(transport: transport, store: store, clock: { fixed })

        // When
        let report = try await engine.syncNow()

        // Then
        XCTAssertEqual(report.lastSyncAt, fixed)
    }

    // MARK: - AsyncStream event ordering

    func test_givenConflictAndPush_whenSyncing_thenEventsOrderedConflictThenDeltaThenPushed() async throws {
        // Given — both a conflict (in the delta) and a pending outbox push.
        let store = try SwiftDataDocumentStore.inMemory()
        await store.upsert(makeDocument(id: "conflict-doc", title: "local", updatedAt: dateAt(0)), localEditedAt: dateAt(5))
        try await store.enqueueOutbox(.updateDocument(id: "push-doc", title: "x", body: nil, folderId: nil, isPublic: nil))
        let transport = StubSyncTransport()
        await transport.enqueuePull(DocumentSyncDelta(documents: [
            makeDocument(id: "conflict-doc", title: "server", updatedAt: dateAt(10))
        ]))
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // Subscribe to events before triggering the cycle.
        let collector = EventCollector()
        let events = engine.events
        let task = Task {
            for await event in events {
                let total = await collector.append(event)
                if total == 3 { break }
            }
        }

        // When
        _ = try await engine.syncNow()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        // Then — exact order: conflictResolved, deltaApplied, pushed.
        let captured = await collector.all
        XCTAssertEqual(captured.count, 3)
        if case .conflictResolved = captured[0] { } else {
            XCTFail("Expected conflictResolved first, got \(captured[0])")
        }
        if case .deltaApplied = captured[1] { } else {
            XCTFail("Expected deltaApplied second, got \(captured[1])")
        }
        if case .pushed = captured[2] { } else {
            XCTFail("Expected pushed third, got \(captured[2])")
        }
    }

    // MARK: - Property-style soak

    func test_givenRandomizedDeltaSequences_whenSyncing_thenFinalStateInvariantsHold() async throws {
        // Given — 50 randomized scenarios. After each cycle:
        //   1. Every non-deleted server doc is present in the store.
        //   2. Every server-deleted doc is absent.
        //   3. The outbox is empty after a successful push cycle.
        for trial in 0..<50 {
            let store = try SwiftDataDocumentStore.inMemory()
            let transport = StubSyncTransport()
            let inserts = (0..<Int.random(in: 0...5)).map { i in
                makeDocument(id: "t\(trial)-i\(i)", title: "v\(i)")
            }
            let deletions = (0..<Int.random(in: 0...3)).map { i in
                makeDocument(id: "t\(trial)-d\(i)", title: "x", deleted: true)
            }
            // Seed a couple of deleted ones first, so the engine has something to drop.
            for doomed in deletions {
                await store.upsert(Document(
                    id: doomed.id,
                    title: doomed.title,
                    updatedAt: dateAt(0)
                ), localEditedAt: nil)
            }
            await transport.enqueuePull(DocumentSyncDelta(documents: inserts + deletions))

            let engine = DocumentSyncEngine(transport: transport, store: store)
            _ = try await engine.syncNow()

            // Invariants
            let cached = await store.allDocuments().map(\.id)
            for ins in inserts {
                XCTAssertTrue(cached.contains(ins.id), "Trial \(trial): expected \(ins.id) present")
            }
            for del in deletions {
                XCTAssertFalse(cached.contains(del.id), "Trial \(trial): expected \(del.id) absent")
            }
            let outbox = await store.outboxEntries()
            XCTAssertTrue(outbox.isEmpty, "Trial \(trial): outbox should be empty after sync")
        }
    }

    // MARK: - Enqueue passthrough

    func test_givenEnqueue_whenCalled_thenChangeStoredInOutbox() async throws {
        // Given
        let store = try SwiftDataDocumentStore.inMemory()
        let transport = StubSyncTransport()
        let engine = DocumentSyncEngine(transport: transport, store: store)

        // When
        await engine.enqueue(.deleteDocument(id: "d"))

        // Then
        let entries = await store.outboxEntries()
        XCTAssertEqual(entries.map { $0.change.targetId }, ["d"])
    }

    // MARK: - Helpers

    private func makeDocument(
        id: String,
        title: String = "t",
        updatedAt: Date = .init(timeIntervalSince1970: 1_700_000_000),
        deleted: Bool = false
    ) -> Document {
        Document(
            id: id,
            folderId: nil,
            title: title,
            body: DocumentBody(markdown: "body"),
            updatedAt: updatedAt,
            createdAt: nil,
            isPublic: false,
            deleted: deleted,
            version: nil
        )
    }

    private func dateAt(_ offsetSeconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offsetSeconds)
    }
}

// MARK: - StubSyncTransport

/// Programmable `DocumentSyncTransport` for the engine tests. Each
/// `enqueuePull` / `enqueuePushOutcome` adds the next outcome; the engine
/// pops them one at a time. Push outcomes default to success when the
/// queue is empty.
actor StubSyncTransport: DocumentSyncTransport {

    enum PushOutcome {
        case success
        case failure(APIError)
    }

    private var pullQueue: [Result<DocumentSyncDelta, APIError>] = []
    private var pushQueue: [PushOutcome] = []
    private(set) var pullCalls: [Date?] = []
    private(set) var pushedChanges: [DocumentChange] = []

    func enqueuePull(_ delta: DocumentSyncDelta) {
        pullQueue.append(.success(delta))
    }

    func enqueuePullFailure(_ error: APIError) {
        pullQueue.append(.failure(error))
    }

    func enqueuePushOutcome(_ outcome: PushOutcome) {
        pushQueue.append(outcome)
    }

    func pullDelta(since: Date?) async throws -> DocumentSyncDelta {
        pullCalls.append(since)
        guard !pullQueue.isEmpty else {
            return DocumentSyncDelta()
        }
        switch pullQueue.removeFirst() {
        case .success(let delta):
            return delta
        case .failure(let error):
            throw error
        }
    }

    func pushChange(_ change: DocumentChange) async throws {
        pushedChanges.append(change)
        let outcome: PushOutcome = pushQueue.isEmpty ? .success : pushQueue.removeFirst()
        if case .failure(let error) = outcome {
            throw error
        }
    }
}

// MARK: - EventCollector

/// Actor-protected buffer for AsyncStream consumer tests under Swift 6
/// strict concurrency.
actor EventCollector {
    private(set) var all: [DocumentSyncEvent] = []

    func append(_ event: DocumentSyncEvent) -> Int {
        all.append(event)
        return all.count
    }
}
