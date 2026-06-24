import Foundation
import SwiftData
import os
import InterlinedDomain

/// SwiftData-backed `DocumentStore` (PLAN.md §3, §6 M4). Mirrors the shape of
/// `SwiftDataListsStore`: an `actor` whose `ModelContext` stays confined to a
/// single isolation domain. All writes best-effort with `os.Logger` for
/// failures, except outbox/sync-state writes which throw to honour the
/// protocol's contract.
///
/// Only `Sendable` value types (`Document`, `FolderNode`, `OutboxEntry`)
/// cross the actor boundary. `@Model` records never escape.
public actor SwiftDataDocumentStore: DocumentStore {

    private let container: ModelContainer
    private var _context: ModelContext?
    private let logger = Logger(
        subsystem: "com.interlinedlist.macos.persistence",
        category: "SwiftDataDocumentStore"
    )

    public init(container: ModelContainer) {
        self.container = container
    }

    /// In-memory factory for tests and previews.
    public static func inMemory() throws -> SwiftDataDocumentStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DocumentRecord.self,
            FolderRecord.self,
            OutboxEntryRecord.self,
            SyncStateRecord.self,
            configurations: configuration
        )
        return SwiftDataDocumentStore(container: container)
    }

    /// On-disk factory. The caller supplies a directory URL; SwiftData
    /// chooses the file name within it.
    public static func onDisk(at url: URL) throws -> SwiftDataDocumentStore {
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: DocumentRecord.self,
            FolderRecord.self,
            OutboxEntryRecord.self,
            SyncStateRecord.self,
            configurations: configuration
        )
        return SwiftDataDocumentStore(container: container)
    }

    // MARK: - Documents

    public func allDocuments() async -> [Document] {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<DocumentRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try context.fetch(descriptor).map { $0.toDocument() }
        } catch {
            logger.error("allDocuments failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func cachedDocument(id: String) async -> Document? {
        let context = self.context
        return fetchDocumentRecord(id: id, context: context)?.toDocument()
    }

    public func localEditedAt(id: String) async -> Date? {
        let context = self.context
        return fetchDocumentRecord(id: id, context: context)?.localEditedAt
    }

    public func upsert(_ document: Document, localEditedAt: Date?) async {
        let context = self.context
        if let existing = fetchDocumentRecord(id: document.id, context: context) {
            existing.apply(document)
            existing.localEditedAt = localEditedAt
        } else {
            context.insert(DocumentRecord(from: document, localEditedAt: localEditedAt))
        }
        save(context, label: "upsert document \(document.id)")
    }

    public func removeDocument(id: String) async {
        let context = self.context
        if let record = fetchDocumentRecord(id: id, context: context) {
            context.delete(record)
            save(context, label: "removeDocument \(id)")
        }
    }

    public func clearLocalEdit(id: String) async {
        let context = self.context
        if let record = fetchDocumentRecord(id: id, context: context) {
            record.localEditedAt = nil
            save(context, label: "clearLocalEdit \(id)")
        }
    }

    // MARK: - Folders

    public func allFolders() async -> [FolderNode] {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<FolderRecord>(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            return try context.fetch(descriptor).map { $0.toFolderNode() }
        } catch {
            logger.error("allFolders failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func cachedFolder(id: String) async -> FolderNode? {
        let context = self.context
        return fetchFolderRecord(id: id, context: context)?.toFolderNode()
    }

    public func upsertFolder(_ folder: FolderNode) async {
        let context = self.context
        if let existing = fetchFolderRecord(id: folder.id, context: context) {
            existing.apply(folder)
        } else {
            context.insert(FolderRecord(from: folder))
        }
        save(context, label: "upsertFolder \(folder.id)")
    }

    public func removeFolder(id: String) async {
        let context = self.context
        do {
            if let record = fetchFolderRecord(id: id, context: context) {
                context.delete(record)
            }
            let folderId = id
            // Cascade: drop every cached document that pointed at this folder.
            // Matches the API's documented behaviour where deleting a folder
            // also removes its documents server-side.
            for doc in try context.fetch(FetchDescriptor<DocumentRecord>(
                predicate: #Predicate { $0.folderId == folderId }
            )) {
                context.delete(doc)
            }
            try context.save()
        } catch {
            logger.error("removeFolder failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Outbox

    public func enqueueOutbox(_ change: DocumentChange) async throws {
        let context = self.context
        let payload = try DocumentChangeCodec.encode(change)
        let row = OutboxEntryRecord(
            kind: change.kind.rawValue,
            targetId: change.targetId,
            payloadJSON: payload,
            enqueuedAt: Date()
        )
        context.insert(row)
        try context.save()
    }

    public func outboxEntries() async -> [OutboxEntry] {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<OutboxEntryRecord>(
                sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
            )
            return try context.fetch(descriptor).compactMap { record in
                guard let change = try? DocumentChangeCodec.decode(record.payloadJSON) else {
                    // Drop unreadable entries silently — the cache is best-effort.
                    logger.error("Dropping outbox entry \(record.id, privacy: .public): unreadable payload")
                    return nil
                }
                return OutboxEntry(
                    id: record.id,
                    change: change,
                    enqueuedAt: record.enqueuedAt,
                    attemptCount: record.attemptCount,
                    lastError: record.lastError
                )
            }
        } catch {
            logger.error("outboxEntries failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func dequeueOutbox(entryId: String) async {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<OutboxEntryRecord>(
                predicate: #Predicate { $0.id == entryId }
            )
            for record in try context.fetch(descriptor) {
                context.delete(record)
            }
            try context.save()
        } catch {
            logger.error("dequeueOutbox failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func markOutboxFailure(entryId: String, message: String) async {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<OutboxEntryRecord>(
                predicate: #Predicate { $0.id == entryId }
            )
            if let record = try context.fetch(descriptor).first {
                record.attemptCount += 1
                record.lastError = message
                try context.save()
            }
        } catch {
            logger.error("markOutboxFailure failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sync state

    public func lastSyncAt() async -> Date? {
        let context = self.context
        return fetchSyncStateRecord(context: context)?.lastSyncAt
    }

    public func lastSyncToken() async -> String? {
        let context = self.context
        return fetchSyncStateRecord(context: context)?.lastSyncToken
    }

    public func updateSyncState(
        lastSyncAt: Date?,
        lastSyncToken: String?,
        pendingOutboxCount: Int
    ) async {
        let context = self.context
        if let existing = fetchSyncStateRecord(context: context) {
            existing.lastSyncAt = lastSyncAt
            existing.lastSyncToken = lastSyncToken
            existing.pendingOutboxCount = pendingOutboxCount
        } else {
            context.insert(SyncStateRecord(
                lastSyncAt: lastSyncAt,
                lastSyncToken: lastSyncToken,
                pendingOutboxCount: pendingOutboxCount
            ))
        }
        save(context, label: "updateSyncState")
    }

    // MARK: - Clear

    public func clear() async {
        let context = self.context
        do {
            try context.delete(model: DocumentRecord.self)
            try context.delete(model: FolderRecord.self)
            try context.delete(model: OutboxEntryRecord.self)
            try context.delete(model: SyncStateRecord.self)
            try context.save()
        } catch {
            logger.error("clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internals

    private var context: ModelContext {
        if let existing = _context { return existing }
        let fresh = ModelContext(container)
        _context = fresh
        return fresh
    }

    private func fetchDocumentRecord(id: String, context: ModelContext) -> DocumentRecord? {
        do {
            let descriptor = FetchDescriptor<DocumentRecord>(
                predicate: #Predicate { $0.id == id }
            )
            return try context.fetch(descriptor).first
        } catch {
            logger.error("fetchDocumentRecord failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchFolderRecord(id: String, context: ModelContext) -> FolderRecord? {
        do {
            let descriptor = FetchDescriptor<FolderRecord>(
                predicate: #Predicate { $0.id == id }
            )
            return try context.fetch(descriptor).first
        } catch {
            logger.error("fetchFolderRecord failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchSyncStateRecord(context: ModelContext) -> SyncStateRecord? {
        do {
            let descriptor = FetchDescriptor<SyncStateRecord>(
                predicate: #Predicate { $0.pageKey == "document-sync" }
            )
            return try context.fetch(descriptor).first
        } catch {
            logger.error("fetchSyncStateRecord failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func save(_ context: ModelContext, label: String) {
        do {
            try context.save()
        } catch {
            logger.error("\(label, privacy: .public) save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - NullDocumentStore

/// No-op `DocumentStore` used when the in-memory / on-disk SwiftData store
/// fails to construct at boot. Matches the `NullMessageStore` /
/// `NullListsStore` pattern.
public struct NullDocumentStore: DocumentStore {

    public init() {}

    public func allDocuments() async -> [Document] { [] }
    public func cachedDocument(id: String) async -> Document? { nil }
    public func localEditedAt(id: String) async -> Date? { nil }
    public func upsert(_ document: Document, localEditedAt: Date?) async {}
    public func removeDocument(id: String) async {}
    public func clearLocalEdit(id: String) async {}

    public func allFolders() async -> [FolderNode] { [] }
    public func cachedFolder(id: String) async -> FolderNode? { nil }
    public func upsertFolder(_ folder: FolderNode) async {}
    public func removeFolder(id: String) async {}

    public func enqueueOutbox(_ change: DocumentChange) async throws {}
    public func outboxEntries() async -> [OutboxEntry] { [] }
    public func dequeueOutbox(entryId: String) async {}
    public func markOutboxFailure(entryId: String, message: String) async {}

    public func lastSyncAt() async -> Date? { nil }
    public func lastSyncToken() async -> String? { nil }
    public func updateSyncState(lastSyncAt: Date?, lastSyncToken: String?, pendingOutboxCount: Int) async {}

    public func clear() async {}
}
