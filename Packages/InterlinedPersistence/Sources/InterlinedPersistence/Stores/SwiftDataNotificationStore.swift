import struct Foundation.Date
import struct Foundation.URL
import SwiftData
import os
import InterlinedDomain

/// Foundation also declares a `Notification` type. We import only the
/// Foundation members we use (`Date`, `URL`) so plain `Notification`
/// resolves unambiguously to the `InterlinedDomain.Notification` value.
typealias DomainNotification = Notification

/// SwiftData-backed notification tray cache (PLAN.md §1 "Notifications", §5
/// stale-while-revalidate, §6 M5).
///
/// Mirrors the `SwiftDataMessageStore` / `SwiftDataListsStore` pattern: an
/// `actor` whose `ModelContext` stays confined to a single isolation domain,
/// all writes best-effort with `os.Logger` for failures. The store does not
/// implement a domain protocol yet — Wave 6.1's M5 brief lands the cache in
/// the persistence layer; the App layer's tray view model can read straight
/// off this store via the composition root or, if a `NotificationStore` port
/// is added in a later wave, by conforming this actor to it without an API
/// change at the call sites.
///
/// Only `Sendable` value types (`Notification`, `NotificationTray`) cross
/// the actor boundary. `@Model` records never escape.
public actor SwiftDataNotificationStore {

    private let container: ModelContainer
    private var _context: ModelContext?
    private let logger = Logger(
        subsystem: "com.interlinedlist.macos.persistence",
        category: "SwiftDataNotificationStore"
    )

    /// Stable singleton key for the tray metadata row.
    private static let trayKey = "tray"

    public init(container: ModelContainer) {
        self.container = container
    }

    /// In-memory factory for tests and previews.
    public static func inMemory() throws -> SwiftDataNotificationStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: NotificationRecord.self,
            NotificationTrayRecord.self,
            configurations: configuration
        )
        return SwiftDataNotificationStore(container: container)
    }

    /// On-disk factory.
    public static func onDisk(at url: URL) throws -> SwiftDataNotificationStore {
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: NotificationRecord.self,
            NotificationTrayRecord.self,
            configurations: configuration
        )
        return SwiftDataNotificationStore(container: container)
    }

    // MARK: - Tray reads / writes

    /// The cached tray (ordered rows + the server-authoritative
    /// `unreadCount`), or an empty value when nothing is cached. The order
    /// of rows is the one captured by the last `replaceTray` call.
    public func cachedTray() async -> NotificationTray {
        let context = self.context
        let trayKey = Self.trayKey
        let (ids, unreadCount): ([String], Int)
        do {
            let descriptor = FetchDescriptor<NotificationTrayRecord>(
                predicate: #Predicate { record in
                    record.pageKey == trayKey
                }
            )
            let record = try context.fetch(descriptor).first
            ids = record?.notificationIDs ?? []
            unreadCount = record?.unreadCount ?? 0
        } catch {
            logger.error("cachedTray fetch failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
        guard !ids.isEmpty else {
            return NotificationTray(unreadCount: unreadCount, items: [])
        }
        let records = fetchRecords(byIDs: ids, context: context)
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let items = ids.compactMap { byID[$0]?.toNotification() }
        return NotificationTray(unreadCount: unreadCount, items: items)
    }

    /// Replaces the cached tray with a fresh server payload.
    public func replaceTray(_ tray: NotificationTray) async {
        let context = self.context
        let trayKey = Self.trayKey

        // 1) Upsert per-row records so by-id reads stay consistent with the
        //    tray slice.
        mergeUpsert(tray.items, context: context)

        // 2) Replace the tray-metadata row.
        do {
            let descriptor = FetchDescriptor<NotificationTrayRecord>(
                predicate: #Predicate { record in
                    record.pageKey == trayKey
                }
            )
            for existing in try context.fetch(descriptor) {
                context.delete(existing)
            }
            let fresh = NotificationTrayRecord(
                pageKey: trayKey,
                unreadCount: tray.unreadCount,
                notificationIDs: tray.items.map(\.id),
                lastFetchedAt: Date()
            )
            context.insert(fresh)
            try context.save()
        } catch {
            logger.error("replaceTray save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One cached notification by id, or `nil` when not cached.
    public func cachedNotification(id: String) async -> DomainNotification? {
        let context = self.context
        return byIDNotification(id: id, context: context)
    }

    /// Insert-or-update a batch of rows in the by-id index. Used by the
    /// service after a tray refresh; also exercised by tests directly.
    public func upsert(_ notifications: [DomainNotification]) async {
        let context = self.context
        mergeUpsert(notifications, context: context)
        do {
            try context.save()
        } catch {
            logger.error("upsert save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Marks a single cached notification read. Also decrements the
    /// cached tray's `unreadCount` (clamped at zero) so the badge stays
    /// in sync without a tray re-fetch. Missing-id is a no-op.
    public func markRead(id: String) async {
        let context = self.context
        do {
            let rowDescriptor = FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { record in record.id == id }
            )
            guard let record = try context.fetch(rowDescriptor).first else {
                return
            }
            guard !record.isRead else { return }
            record.isRead = true
            record.readAt = Date()

            let trayKey = Self.trayKey
            let trayDescriptor = FetchDescriptor<NotificationTrayRecord>(
                predicate: #Predicate { record in record.pageKey == trayKey }
            )
            if let tray = try context.fetch(trayDescriptor).first {
                tray.unreadCount = max(0, tray.unreadCount - 1)
            }
            try context.save()
        } catch {
            logger.error("markRead failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Marks every cached notification read and zeroes `unreadCount`. Used
    /// by the service after a `markAllRead` success.
    public func markAllRead() async {
        let context = self.context
        do {
            let rowDescriptor = FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { record in record.isRead == false }
            )
            let now = Date()
            for row in try context.fetch(rowDescriptor) {
                row.isRead = true
                row.readAt = now
            }
            let trayKey = Self.trayKey
            let trayDescriptor = FetchDescriptor<NotificationTrayRecord>(
                predicate: #Predicate { record in record.pageKey == trayKey }
            )
            if let tray = try context.fetch(trayDescriptor).first {
                tray.unreadCount = 0
            }
            try context.save()
        } catch {
            logger.error("markAllRead failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drop every cached value (every notification row and the tray
    /// metadata). Called on sign-out.
    public func clear() async {
        let context = self.context
        do {
            try context.delete(model: NotificationTrayRecord.self)
            try context.delete(model: NotificationRecord.self)
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

    private func fetchRecords(byIDs ids: [String], context: ModelContext) -> [NotificationRecord] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        do {
            let descriptor = FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { record in
                    idSet.contains(record.id)
                }
            )
            return try context.fetch(descriptor)
        } catch {
            logger.error("fetchRecords failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func byIDNotification(id: String, context: ModelContext) -> DomainNotification? {
        do {
            let descriptor = FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { record in record.id == id }
            )
            return try context.fetch(descriptor).first?.toNotification()
        } catch {
            logger.error("byIDNotification fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func mergeUpsert(_ notifications: [InterlinedDomain.Notification], context: ModelContext) {
        for notification in notifications {
            let id = notification.id
            do {
                let descriptor = FetchDescriptor<NotificationRecord>(
                    predicate: #Predicate { record in record.id == id }
                )
                if let existing = try context.fetch(descriptor).first {
                    existing.apply(notification)
                } else {
                    context.insert(NotificationRecord(from: notification))
                }
            } catch {
                logger.error(
                    "mergeUpsert failed for id \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
