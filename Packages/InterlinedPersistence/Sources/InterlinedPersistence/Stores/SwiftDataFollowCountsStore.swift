import Foundation
import SwiftData
import os
import InterlinedDomain

/// SwiftData-backed cache for per-user follow counts (PLAN.md §1 "Follow
/// system", §5 stale-while-revalidate, §6 M5).
///
/// One row per user id, holding the public follow counts (`FollowCounts`)
/// and the mutual-follow counts (`MutualCounts`) the M5 profile header
/// renders. The profile view paints instantly from the cache before the
/// network refresh lands; the service is expected to write the freshest
/// payload through after every successful read.
///
/// Mirrors the actor + best-effort `os.Logger` pattern from
/// `SwiftDataMessageStore` and `SwiftDataListsStore`. Only `Sendable` value
/// types (`FollowCounts`, `MutualCounts`, `CachedFollowCounts`) cross the
/// actor boundary; the `@Model` records never escape.
public actor SwiftDataFollowCountsStore {

    private let container: ModelContainer
    private var _context: ModelContext?
    private let logger = Logger(
        subsystem: "com.interlinedlist.macos.persistence",
        category: "SwiftDataFollowCountsStore"
    )

    public init(container: ModelContainer) {
        self.container = container
    }

    /// In-memory factory for tests and previews.
    public static func inMemory() throws -> SwiftDataFollowCountsStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FollowCountsRecord.self,
            configurations: configuration
        )
        return SwiftDataFollowCountsStore(container: container)
    }

    /// On-disk factory.
    public static func onDisk(at url: URL) throws -> SwiftDataFollowCountsStore {
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: FollowCountsRecord.self,
            configurations: configuration
        )
        return SwiftDataFollowCountsStore(container: container)
    }

    // MARK: - Reads

    /// The cached counts for a user, or `nil` when nothing is cached.
    /// Returns the combined `CachedFollowCounts` value so the M5 profile
    /// view can render the header in one paint.
    public func cached(userID: String) async -> CachedFollowCounts? {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<FollowCountsRecord>(
                predicate: #Predicate { record in record.userID == userID }
            )
            guard let record = try context.fetch(descriptor).first else {
                return nil
            }
            return CachedFollowCounts(
                userID: record.userID,
                follow: FollowCounts(followers: record.followers, following: record.following),
                mutual: MutualCounts(
                    mutualFollowers: record.mutualFollowers,
                    mutualFollowing: record.mutualFollowing
                ),
                fetchedAt: record.fetchedAt
            )
        } catch {
            logger.error("cached fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Writes

    /// Upserts the follow-count side of the row, leaving the mutual side
    /// alone (so a profile-load refresh of follower / following counts
    /// does not clobber the M5 mutual badges).
    public func cacheFollowCounts(_ counts: FollowCounts, for userID: String) async {
        let context = self.context
        do {
            let record = try fetchOrCreate(userID: userID, context: context)
            record.followers = counts.followers
            record.following = counts.following
            record.fetchedAt = Date()
            try context.save()
        } catch {
            logger.error("cacheFollowCounts save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Upserts the mutual side of the row, leaving the follower / following
    /// counts alone.
    public func cacheMutualCounts(_ counts: MutualCounts, for userID: String) async {
        let context = self.context
        do {
            let record = try fetchOrCreate(userID: userID, context: context)
            record.mutualFollowers = counts.mutualFollowers
            record.mutualFollowing = counts.mutualFollowing
            record.fetchedAt = Date()
            try context.save()
        } catch {
            logger.error("cacheMutualCounts save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the cached row for a user. Missing-id is a no-op.
    public func remove(userID: String) async {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<FollowCountsRecord>(
                predicate: #Predicate { record in record.userID == userID }
            )
            for record in try context.fetch(descriptor) {
                context.delete(record)
            }
            try context.save()
        } catch {
            logger.error("remove failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops every cached row. Called on sign-out.
    public func clear() async {
        let context = self.context
        do {
            try context.delete(model: FollowCountsRecord.self)
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

    private func fetchOrCreate(userID: String, context: ModelContext) throws -> FollowCountsRecord {
        let descriptor = FetchDescriptor<FollowCountsRecord>(
            predicate: #Predicate { record in record.userID == userID }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let fresh = FollowCountsRecord(userID: userID)
        context.insert(fresh)
        return fresh
    }
}

// MARK: - CachedFollowCounts

/// The value-typed projection of a cached `FollowCountsRecord`, returned by
/// `SwiftDataFollowCountsStore.cached(userID:)`. Carries the combined
/// follower / following / mutual counts plus the `fetchedAt` timestamp so
/// callers can render a "Last updated …" badge without a second lookup.
public struct CachedFollowCounts: Sendable, Equatable {
    public let userID: String
    public let follow: FollowCounts
    public let mutual: MutualCounts
    public let fetchedAt: Date

    public init(
        userID: String,
        follow: FollowCounts,
        mutual: MutualCounts,
        fetchedAt: Date
    ) {
        self.userID = userID
        self.follow = follow
        self.mutual = mutual
        self.fetchedAt = fetchedAt
    }
}
