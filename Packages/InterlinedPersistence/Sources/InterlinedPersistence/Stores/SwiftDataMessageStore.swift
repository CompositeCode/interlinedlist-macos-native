import Foundation
import SwiftData
import os
import InterlinedDomain

/// SwiftData-backed `MessageStore` (PLAN.md §3, §5). Conforms to the cache
/// port in `InterlinedDomain` so `MessagesService` can be wired up with a
/// durable cache in the app and an `InMemoryMessageStore` in tests.
///
/// Implemented as an `actor` so:
/// - `ModelContext` (which is not thread-safe and not `Sendable`) is
///   confined to a single isolation domain;
/// - the protocol's non-throwing async methods compose cleanly under Swift
///   6 strict concurrency;
/// - mutable internal state needs no manual locking.
///
/// Only `Sendable` value types (`Message`, `[Message]`, `Message?`) cross
/// the actor boundary. `@Model` records never escape.
///
/// All SwiftData throws are caught and logged via `os.Logger` — per the
/// `MessageStore` contract the cache is best-effort and must never break
/// a live fetch (see `MessageStore.swift` docs).
public actor SwiftDataMessageStore: MessageStore {

    private let container: ModelContainer
    /// Lazily created on first use so the actor owns sole reference to its
    /// context — `ModelContext` is not `Sendable`, so we keep it strictly
    /// actor-isolated.
    private var _context: ModelContext?
    private let logger = Logger(
        subsystem: "com.interlinedlist.macos.persistence",
        category: "SwiftDataMessageStore"
    )

    /// Designated initializer. The caller owns the `ModelContainer` so the
    /// app can share one container across multiple stores or screens.
    public init(container: ModelContainer) {
        self.container = container
    }

    /// Convenience factory that returns a fully in-memory store, intended
    /// for tests and previews. Leaves no disk artifacts.
    ///
    /// Throws if `ModelContainer` cannot be constructed — which on a
    /// well-formed schema would only happen for runtime reasons (sandbox,
    /// memory). Tests that hit this should fail loudly rather than
    /// silently degrade, hence the throwing factory.
    public static func inMemory() throws -> SwiftDataMessageStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MessageRecord.self, TimelinePageRecord.self,
            configurations: configuration
        )
        return SwiftDataMessageStore(container: container)
    }

    // MARK: - MessageStore

    public func cachedTimeline(scope: TimelineScope, tag: String?) async -> [Message] {
        let context = self.context
        let scopeKey = scope.rawScopeKey
        let ids: [String]
        do {
            let descriptor = timelinePageFetchDescriptor(scopeKey: scopeKey, tag: tag)
            let page = try context.fetch(descriptor).first
            ids = page?.messageIDs ?? []
        } catch {
            logger.error("cachedTimeline fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        guard !ids.isEmpty else { return [] }

        // Hydrate by id, preserving order. A single fetch over the id-set
        // is cheaper than N point fetches, then we reorder in memory.
        let records = fetchRecords(byIDs: ids, context: context)
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return ids.compactMap { id in
            recordsByID[id]?.toMessage { originalID in
                // Cheap repost re-hydration: look up the original message in
                // the same fetched batch first, then fall back to the by-id
                // index for off-page reposts.
                recordsByID[originalID]?.toMessage(repostLookup: { _ in nil })
                    ?? self.byIDMessage(id: originalID, context: context)
            }
        }
    }

    public func replaceTimeline(_ messages: [Message], scope: TimelineScope, tag: String?) async {
        let context = self.context
        let scopeKey = scope.rawScopeKey

        // 1) Upsert message records so by-id reads stay consistent with the
        //    timeline slice (matches InMemoryMessageStore.replaceTimeline,
        //    which writes to both indexes).
        mergeUpsert(messages, context: context)

        // 2) Replace the page record for this (scope, tag) key.
        do {
            let descriptor = timelinePageFetchDescriptor(scopeKey: scopeKey, tag: tag)
            let existing = try context.fetch(descriptor)
            for page in existing { context.delete(page) }
            let fresh = TimelinePageRecord(
                scopeRaw: scopeKey,
                tag: tag,
                messageIDs: messages.map(\.id),
                fetchedAt: Date()
            )
            context.insert(fresh)
            try context.save()
        } catch {
            logger.error("replaceTimeline save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func cachedMessage(id: String) async -> Message? {
        let context = self.context
        return byIDMessage(id: id, context: context)
    }

    public func upsert(_ messages: [Message]) async {
        let context = self.context
        mergeUpsert(messages, context: context)
        do {
            try context.save()
        } catch {
            logger.error("upsert save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func clear() async {
        let context = self.context
        do {
            try context.delete(model: TimelinePageRecord.self)
            try context.delete(model: MessageRecord.self)
            try context.save()
        } catch {
            logger.error("clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internals

    /// Lazy `ModelContext` accessor. Created once per actor instance and
    /// reused; staying actor-isolated means we never need a `MainActor`
    /// context here.
    private var context: ModelContext {
        if let existing = _context { return existing }
        let fresh = ModelContext(container)
        _context = fresh
        return fresh
    }

    private func timelinePageFetchDescriptor(
        scopeKey: String,
        tag: String?
    ) -> FetchDescriptor<TimelinePageRecord> {
        // SwiftData predicates on macOS 14 do not always optimize an
        // optional-equality cleanly; splitting on `tag == nil` avoids the
        // edge case and produces a simpler predicate either way.
        if let tag {
            return FetchDescriptor<TimelinePageRecord>(
                predicate: #Predicate { record in
                    record.scopeRaw == scopeKey && record.tag == tag
                }
            )
        } else {
            return FetchDescriptor<TimelinePageRecord>(
                predicate: #Predicate { record in
                    record.scopeRaw == scopeKey && record.tag == nil
                }
            )
        }
    }

    private func fetchRecords(byIDs ids: [String], context: ModelContext) -> [MessageRecord] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        do {
            let descriptor = FetchDescriptor<MessageRecord>(
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

    private func byIDMessage(id: String, context: ModelContext) -> Message? {
        do {
            let descriptor = FetchDescriptor<MessageRecord>(
                predicate: #Predicate { record in record.id == id }
            )
            guard let record = try context.fetch(descriptor).first else { return nil }
            return record.toMessage { originalID in
                // Single-hop lookup for the repost target. If it isn't in
                // the cache we drop it — best-effort per the protocol.
                self.byIDMessage(id: originalID, context: context).map { $0 }
            }
        } catch {
            logger.error("cachedMessage fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Insert-or-update by id, without saving. Caller decides when to
    /// `save()`. SwiftData on macOS 14 lacks a declarative upsert, so we
    /// fetch by id and mutate when present.
    private func mergeUpsert(_ messages: [Message], context: ModelContext) {
        for message in messages {
            let id = message.id
            do {
                let descriptor = FetchDescriptor<MessageRecord>(
                    predicate: #Predicate { record in record.id == id }
                )
                if let existing = try context.fetch(descriptor).first {
                    existing.apply(message)
                } else {
                    context.insert(MessageRecord(from: message))
                }
            } catch {
                logger.error("mergeUpsert failed for id \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
