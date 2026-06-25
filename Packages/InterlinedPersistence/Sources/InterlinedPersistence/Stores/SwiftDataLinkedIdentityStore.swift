import Foundation
import SwiftData
import os
import InterlinedDomain

/// SwiftData-backed cache for the signed-in account's linked OAuth identities
/// (PLAN.md §1 "Profile & account / linked identities", §5
/// stale-while-revalidate, §6 M6 — OAuth identity linking).
///
/// A single-user cache: the rows are the current account's identities, so the
/// store carries no per-user discriminator. `replaceIdentities` clears and
/// rewrites the whole set on each refresh — the documented house pattern for
/// a list-of-one-thing that the server returns wholesale (the same
/// full-replace semantics `SwiftDataNotificationStore.replaceTray` and
/// `SwiftDataListsStore.cacheRows` use). A dedicated actor (rather than
/// folding into `SwiftDataOrgStore`) keeps the sign-out / account-switch
/// lifecycle and the wholesale-replace semantics independent from the
/// per-org, per-member org cache.
///
/// Mirrors the `SwiftDataFollowCountsStore` actor + best-effort `os.Logger`
/// pattern. Only `Sendable` `LinkedIdentity` values cross the actor boundary;
/// the `@Model` record never escapes.
public actor SwiftDataLinkedIdentityStore {

    private let container: ModelContainer
    private var _context: ModelContext?
    private let logger = Logger(
        subsystem: "com.interlinedlist.macos.persistence",
        category: "SwiftDataLinkedIdentityStore"
    )

    public init(container: ModelContainer) {
        self.container = container
    }

    /// In-memory factory for tests and previews.
    public static func inMemory() throws -> SwiftDataLinkedIdentityStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LinkedIdentityRecord.self,
            configurations: configuration
        )
        return SwiftDataLinkedIdentityStore(container: container)
    }

    /// On-disk factory.
    public static func onDisk(at url: URL) throws -> SwiftDataLinkedIdentityStore {
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: LinkedIdentityRecord.self,
            configurations: configuration
        )
        return SwiftDataLinkedIdentityStore(container: container)
    }

    // MARK: - Reads

    /// Every cached identity, ordered by `id` for a stable read order.
    /// Empty array when nothing is cached.
    public func cachedIdentities() async -> [LinkedIdentity] {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<LinkedIdentityRecord>(
                sortBy: [SortDescriptor(\.id, order: .forward)]
            )
            return try context.fetch(descriptor).map { $0.toLinkedIdentity() }
        } catch {
            logger.error("cachedIdentities fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// One cached identity by id, or `nil` when not cached.
    public func cachedIdentity(id: String) async -> LinkedIdentity? {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<LinkedIdentityRecord>(
                predicate: #Predicate { record in record.id == id }
            )
            return try context.fetch(descriptor).first?.toLinkedIdentity()
        } catch {
            logger.error("cachedIdentity fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Writes

    /// Replaces the entire cached identity set with a fresh server payload.
    /// Full-replace semantics: unlinking an identity on another device shows
    /// up as that row disappearing from the cache after the next refresh.
    public func replaceIdentities(_ identities: [LinkedIdentity]) async {
        let context = self.context
        do {
            try context.delete(model: LinkedIdentityRecord.self)
            for identity in identities {
                context.insert(LinkedIdentityRecord(from: identity))
            }
            try context.save()
        } catch {
            logger.error("replaceIdentities save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes one identity by id from the cache. Missing-id is a no-op.
    public func removeIdentity(id: String) async {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<LinkedIdentityRecord>(
                predicate: #Predicate { record in record.id == id }
            )
            for record in try context.fetch(descriptor) {
                context.delete(record)
            }
            try context.save()
        } catch {
            logger.error("removeIdentity failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops every cached identity. Called on sign-out / account switch.
    public func clear() async {
        let context = self.context
        do {
            try context.delete(model: LinkedIdentityRecord.self)
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
}
