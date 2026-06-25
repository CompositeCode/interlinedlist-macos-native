import Foundation
import SwiftData
import os
import InterlinedDomain

/// SwiftData-backed cache for organizations and their members (PLAN.md §1
/// "Organizations", §5 stale-while-revalidate, §6 M6 — org switcher + member
/// management with roles).
///
/// Mirrors the `SwiftDataFollowCountsStore` / `SwiftDataNotificationStore`
/// shape: an `actor` whose `ModelContext` stays confined to a single
/// isolation domain, all writes best-effort with `os.Logger` for failures.
/// The store does not implement a domain protocol yet — the M6 brief lands
/// the cache; a later wave can conform this actor to an `OrgStore` port
/// without changing the call sites.
///
/// Member rows are keyed to their org by a flat `orgID` discriminator on
/// `OrgMemberRecord` (the same shape `ListRowRecord.listID` uses), so per-org
/// isolation is a single predicate fetch and there is no modelled-relationship
/// cascade to maintain.
///
/// Only `Sendable` value types (`Organization`, `OrgMember`) cross the actor
/// boundary; the `@Model` records never escape.
public actor SwiftDataOrgStore {

    private let container: ModelContainer
    private var _context: ModelContext?
    private let logger = Logger(
        subsystem: "com.interlinedlist.macos.persistence",
        category: "SwiftDataOrgStore"
    )

    public init(container: ModelContainer) {
        self.container = container
    }

    /// In-memory factory for tests and previews.
    public static func inMemory() throws -> SwiftDataOrgStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OrgRecord.self,
            OrgMemberRecord.self,
            configurations: configuration
        )
        return SwiftDataOrgStore(container: container)
    }

    /// On-disk factory.
    public static func onDisk(at url: URL) throws -> SwiftDataOrgStore {
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: OrgRecord.self,
            OrgMemberRecord.self,
            configurations: configuration
        )
        return SwiftDataOrgStore(container: container)
    }

    // MARK: - Organization reads

    /// Every cached organization. Order is not guaranteed (callers sort for
    /// display) — the page envelope (`hasMore` / `nextOffset`) is a
    /// service-layer concern and is not persisted.
    public func cachedOrganizations() async -> [Organization] {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<OrgRecord>()
            return try context.fetch(descriptor).map { $0.toOrganization() }
        } catch {
            logger.error("cachedOrganizations fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// One cached organization by id, or `nil` when not cached.
    public func cachedOrganization(id: String) async -> Organization? {
        let context = self.context
        return fetchOrgRecord(id: id, context: context)?.toOrganization()
    }

    // MARK: - Organization writes

    /// Insert-or-update a batch of organizations (second-write-wins per id).
    /// Used after an orgs-page refresh.
    public func cacheOrganizations(_ organizations: [Organization]) async {
        let context = self.context
        mergeUpsertOrgs(organizations, context: context)
        do {
            try context.save()
        } catch {
            logger.error("cacheOrganizations save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Insert-or-update a single organization.
    public func cacheOrganization(_ organization: Organization) async {
        let context = self.context
        mergeUpsertOrgs([organization], context: context)
        do {
            try context.save()
        } catch {
            logger.error("cacheOrganization save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Member reads

    /// The cached members for an org, or an empty array when none are cached.
    /// Sorted by `userId` for a stable read order (the API's page order is a
    /// service-layer concern; the cache keys by user, not by position).
    public func cachedMembers(of orgID: String) async -> [OrgMember] {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<OrgMemberRecord>(
                predicate: #Predicate { record in record.orgID == orgID },
                sortBy: [SortDescriptor(\.userId, order: .forward)]
            )
            return try context.fetch(descriptor).map { $0.toOrgMember() }
        } catch {
            logger.error("cachedMembers fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Member writes

    /// Replaces the cached member slice for one org with a fresh payload.
    /// Page semantics: a new call fully replaces the previous member set for
    /// that org (mirrors `SwiftDataListsStore.cacheRows`), so removed members
    /// disappear from the cache. Other orgs' members are untouched.
    public func cacheMembers(_ members: [OrgMember], of orgID: String) async {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<OrgMemberRecord>(
                predicate: #Predicate { record in record.orgID == orgID }
            )
            for existing in try context.fetch(descriptor) {
                context.delete(existing)
            }
            for member in members {
                context.insert(OrgMemberRecord(from: member, orgID: orgID))
            }
            try context.save()
        } catch {
            logger.error("cacheMembers save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Insert-or-update a single member of an org (second-write-wins on the
    /// (`orgID`, `userId`) pair). Used after a member-mutation response (add /
    /// update role) so the roster stays current without a full re-fetch.
    public func upsertMember(_ member: OrgMember, in orgID: String) async {
        let context = self.context
        mergeUpsertMember(member, orgID: orgID, context: context)
        do {
            try context.save()
        } catch {
            logger.error("upsertMember save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes one member from one org's cache. Missing pair is a no-op.
    public func removeMember(userId: String, from orgID: String) async {
        let context = self.context
        do {
            let descriptor = FetchDescriptor<OrgMemberRecord>(
                predicate: #Predicate { record in
                    record.orgID == orgID && record.userId == userId
                }
            )
            for record in try context.fetch(descriptor) {
                context.delete(record)
            }
            try context.save()
        } catch {
            logger.error("removeMember failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - remove / clear

    /// Removes one org and all its cached members (clear-cascade for a single
    /// org). Missing-id is a no-op.
    public func removeOrganization(id: String) async {
        let context = self.context
        do {
            if let record = fetchOrgRecord(id: id, context: context) {
                context.delete(record)
            }
            let orgID = id
            let memberDescriptor = FetchDescriptor<OrgMemberRecord>(
                predicate: #Predicate { record in record.orgID == orgID }
            )
            for member in try context.fetch(memberDescriptor) {
                context.delete(member)
            }
            try context.save()
        } catch {
            logger.error("removeOrganization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops every cached org and member row. Called on sign-out.
    public func clear() async {
        let context = self.context
        do {
            try context.delete(model: OrgMemberRecord.self)
            try context.delete(model: OrgRecord.self)
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

    private func fetchOrgRecord(id: String, context: ModelContext) -> OrgRecord? {
        do {
            let descriptor = FetchDescriptor<OrgRecord>(
                predicate: #Predicate { record in record.id == id }
            )
            return try context.fetch(descriptor).first
        } catch {
            logger.error("fetchOrgRecord failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func mergeUpsertOrgs(_ organizations: [Organization], context: ModelContext) {
        for organization in organizations {
            let id = organization.id
            do {
                let descriptor = FetchDescriptor<OrgRecord>(
                    predicate: #Predicate { record in record.id == id }
                )
                if let existing = try context.fetch(descriptor).first {
                    existing.apply(organization)
                } else {
                    context.insert(OrgRecord(from: organization))
                }
            } catch {
                logger.error(
                    "mergeUpsertOrgs failed for id \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func mergeUpsertMember(_ member: OrgMember, orgID: String, context: ModelContext) {
        let userId = member.userId
        do {
            let descriptor = FetchDescriptor<OrgMemberRecord>(
                predicate: #Predicate { record in
                    record.orgID == orgID && record.userId == userId
                }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.apply(member)
            } else {
                context.insert(OrgMemberRecord(from: member, orgID: orgID))
            }
        } catch {
            logger.error(
                "mergeUpsertMember failed for \(orgID, privacy: .public)/\(userId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
