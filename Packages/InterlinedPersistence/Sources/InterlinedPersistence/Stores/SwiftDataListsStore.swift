import Foundation
import SwiftData
import os
import InterlinedDomain

/// SwiftData-backed `ListsStore` (PLAN.md §3, §5). Mirrors the
/// `SwiftDataMessageStore` shape: an `actor` whose `ModelContext` stays
/// confined to a single isolation domain, all writes best-effort with
/// `os.Logger` for failures.
///
/// Only `Sendable` value types (`OwnedList`, `ListRow`, …) cross the actor
/// boundary. `@Model` records never escape.
public actor SwiftDataListsStore: ListsStore {

    private let container: ModelContainer
    private var _context: ModelContext?
    private let logger = Logger(
        subsystem: "com.interlinedlist.macos.persistence",
        category: "SwiftDataListsStore"
    )

    /// The constant key the owned-list page is stored under.
    private static let ownedListsPageKey = "my-lists"

    public init(container: ModelContainer) {
        self.container = container
    }

    /// In-memory factory for tests and previews.
    public static func inMemory() throws -> SwiftDataListsStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ListRecord.self,
            ListsPageRecord.self,
            ListSchemaRecord.self,
            SchemaFieldRecord.self,
            ListRowRecord.self,
            ListConnectionRecord.self,
            ListWatcherRecord.self,
            configurations: configuration
        )
        return SwiftDataListsStore(container: container)
    }

    /// On-disk factory. The caller supplies a directory URL; SwiftData
    /// chooses the file name within it.
    public static func onDisk(at url: URL) throws -> SwiftDataListsStore {
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: ListRecord.self,
            ListsPageRecord.self,
            ListSchemaRecord.self,
            SchemaFieldRecord.self,
            ListRowRecord.self,
            ListConnectionRecord.self,
            ListWatcherRecord.self,
            configurations: configuration
        )
        return SwiftDataListsStore(container: container)
    }

    // MARK: - ListsStore

    public func cachedLists() async -> [OwnedList] {
        let context = self.context
        let pageKey = Self.ownedListsPageKey
        let ids: [String]
        do {
            let descriptor = FetchDescriptor<ListsPageRecord>(
                predicate: #Predicate { record in
                    record.pageKey == pageKey
                }
            )
            ids = (try context.fetch(descriptor).first)?.listIDs ?? []
        } catch {
            logger.error("cachedLists fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        guard !ids.isEmpty else { return [] }
        let records = fetchListRecords(byIDs: ids, context: context)
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return ids.compactMap { byID[$0]?.toOwnedList() }
    }

    public func cacheLists(_ lists: [OwnedList]) async {
        let context = self.context
        let pageKey = Self.ownedListsPageKey
        mergeUpsertLists(lists, context: context)
        do {
            let descriptor = FetchDescriptor<ListsPageRecord>(
                predicate: #Predicate { record in
                    record.pageKey == pageKey
                }
            )
            for existing in try context.fetch(descriptor) {
                context.delete(existing)
            }
            let fresh = ListsPageRecord(
                pageKey: pageKey,
                listIDs: lists.map(\.id),
                fetchedAt: Date()
            )
            context.insert(fresh)
            try context.save()
        } catch {
            logger.error("cacheLists save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func cachedList(id: String) async -> OwnedList? {
        let context = self.context
        return fetchListRecord(id: id, context: context)?.toOwnedList()
    }

    public func cacheList(_ list: OwnedList) async {
        let context = self.context
        mergeUpsertLists([list], context: context)
        do {
            try context.save()
        } catch {
            logger.error("cacheList save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func removeList(id: String) async {
        let context = self.context
        do {
            if let record = fetchListRecord(id: id, context: context) {
                context.delete(record)
            }
            // Drop dependent rows / schema / watchers for this list to
            // keep the cache consistent. Connections involving the list
            // are deleted too — a dangling edge is a half-rendered graph.
            let listID = id
            for row in try context.fetch(FetchDescriptor<ListRowRecord>(
                predicate: #Predicate { $0.listID == listID }
            )) {
                context.delete(row)
            }
            for schemaRecord in try context.fetch(FetchDescriptor<ListSchemaRecord>(
                predicate: #Predicate { $0.listID == listID }
            )) {
                context.delete(schemaRecord)
            }
            for watcher in try context.fetch(FetchDescriptor<ListWatcherRecord>(
                predicate: #Predicate { $0.listID == listID }
            )) {
                context.delete(watcher)
            }
            for edge in try context.fetch(FetchDescriptor<ListConnectionRecord>(
                predicate: #Predicate { record in
                    record.fromListID == listID || record.toListID == listID
                }
            )) {
                context.delete(edge)
            }
            // Evict from the page index too.
            let pageKey = Self.ownedListsPageKey
            let pageDescriptor = FetchDescriptor<ListsPageRecord>(
                predicate: #Predicate { record in record.pageKey == pageKey }
            )
            if let page = try context.fetch(pageDescriptor).first {
                let filtered = page.listIDs.filter { $0 != id }
                if filtered.count != page.listIDs.count {
                    page.listIDs = filtered
                }
            }
            try context.save()
        } catch {
            logger.error("removeList failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func cachedRows(of listId: String) async -> [ListRow] {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<ListRowRecord>(
                predicate: #Predicate { record in record.listID == listId },
                sortBy: [SortDescriptor(\.position, order: .forward)]
            )
            let records = try context.fetch(descriptor)
            return records.map { $0.toListRow() }
        } catch {
            logger.error("cachedRows failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func cacheRows(_ rows: [ListRow], of listId: String) async {
        let context = self.context
        do {
            // Drop the prior slice for this list — page semantics: a new
            // call to `cacheRows` fully replaces the previous one. This
            // keeps the on-disk shape consistent with the API's pagination
            // semantics, mirroring `replaceTimeline`.
            let descriptor = FetchDescriptor<ListRowRecord>(
                predicate: #Predicate { record in record.listID == listId }
            )
            for existing in try context.fetch(descriptor) {
                context.delete(existing)
            }
            for (index, row) in rows.enumerated() {
                context.insert(ListRowRecord(from: row, listID: listId, position: index))
            }
            try context.save()
        } catch {
            logger.error("cacheRows save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func clear() async {
        let context = self.context
        do {
            try context.delete(model: ListsPageRecord.self)
            try context.delete(model: ListRecord.self)
            try context.delete(model: ListSchemaRecord.self)
            try context.delete(model: SchemaFieldRecord.self)
            try context.delete(model: ListRowRecord.self)
            try context.delete(model: ListConnectionRecord.self)
            try context.delete(model: ListWatcherRecord.self)
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

    private func fetchListRecord(id: String, context: ModelContext) -> ListRecord? {
        do {
            let descriptor = FetchDescriptor<ListRecord>(
                predicate: #Predicate { $0.id == id }
            )
            return try context.fetch(descriptor).first
        } catch {
            logger.error("fetchListRecord failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchListRecords(byIDs ids: [String], context: ModelContext) -> [ListRecord] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        do {
            let descriptor = FetchDescriptor<ListRecord>(
                predicate: #Predicate { record in idSet.contains(record.id) }
            )
            return try context.fetch(descriptor)
        } catch {
            logger.error("fetchListRecords failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func mergeUpsertLists(_ lists: [OwnedList], context: ModelContext) {
        for list in lists {
            let id = list.id
            do {
                let descriptor = FetchDescriptor<ListRecord>(
                    predicate: #Predicate { record in record.id == id }
                )
                if let existing = try context.fetch(descriptor).first {
                    existing.apply(list)
                } else {
                    context.insert(ListRecord(from: list))
                }
            } catch {
                logger.error("mergeUpsertLists failed for id \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - NullListsStore

/// No-op `ListsStore` used when the in-memory / on-disk SwiftData store
/// fails to construct at boot (matches the `NullMessageStore` pattern
/// recorded in the App composition root). The service treats the cache as
/// best-effort, so a no-op store is a safe degraded mode.
public struct NullListsStore: ListsStore {

    public init() {}

    public func cachedLists() async -> [OwnedList] { [] }
    public func cacheLists(_ lists: [OwnedList]) async {}
    public func cachedList(id: String) async -> OwnedList? { nil }
    public func cacheList(_ list: OwnedList) async {}
    public func removeList(id: String) async {}
    public func cachedRows(of listId: String) async -> [ListRow] { [] }
    public func cacheRows(_ rows: [ListRow], of listId: String) async {}
    public func clear() async {}
}
