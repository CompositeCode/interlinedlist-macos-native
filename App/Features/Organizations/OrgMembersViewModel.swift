// OrgMembersViewModel
//
// Drives the org member roster and its management actions (PLAN.md §1
// "Organizations" — "member management with roles", §6 M6). Loads one
// page of members at a time (`OrgService.members(of:)`) and supports
// optimistic role promote / demote (`updateMember`), add-member
// (`addMember`), and remove-member (`removeMember`).
//
// Every mutation follows the proven optimistic pattern: snapshot the
// roster, mutate locally, call the service, then on success replace the
// optimistic copy with the server's authoritative return value (role
// changes / adds return the canonical membership). On failure, restore
// the snapshot and surface the error. A `pendingOperations` set keyed by
// userId debounces rapid toggles so the same member can't double-fire.
//
// Reads through `OrgServicing` only — no direct API access — so unit
// tests substitute a stub. `@Observable` so SwiftUI re-renders on every
// state change.
//
// Per decision 0003, the view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class OrgMembersViewModel {

    // MARK: - Dependencies

    private let orgs: OrgServicing
    private let orgId: String

    /// Page size for member pagination. Mirrors the kit's default `limit`.
    static let pageSize: Int = 20

    // MARK: - Observable state

    private(set) var members: [OrgMember] = []
    private(set) var hasMore: Bool = false
    private(set) var nextOffset: Int?

    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// The most recent management-action error (role change / add / remove).
    /// Distinct from `loadError` so a failed mutation doesn't blank the list.
    private(set) var actionError: Error?

    /// User ids with a mutation in flight — debounces rapid toggling and
    /// drives per-row spinners / disabled controls.
    private(set) var pendingOperations: Set<String> = []

    // MARK: - Init

    init(orgService: OrgServicing, orgId: String) {
        self.orgs = orgService
        self.orgId = orgId
    }

    // MARK: - Loading

    /// Loads members. `reset: true` starts from offset 0 (initial load /
    /// refresh); `reset: false` appends the next page for infinite scroll.
    func load(reset: Bool = false) async {
        guard !isLoading else { return }
        if reset {
            members = []
            hasMore = false
            nextOffset = nil
            loadError = nil
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let offset = nextOffset ?? 0
            let page = try await orgs.members(
                of: orgId,
                limit: Self.pageSize,
                offset: offset
            )
            if reset {
                members = page.members
            } else {
                members.append(contentsOf: page.members)
            }
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            loadError = nil
        } catch {
            loadError = error
        }
    }

    // MARK: - Role change (optimistic)

    /// Promotes / demotes a member to a new role. Optimistically swaps the
    /// row's role, calls `updateMember`, and on success replaces the
    /// optimistic row with the server's authoritative membership. On failure,
    /// restores the snapshot and surfaces the error.
    ///
    /// A no-op if the member is already at `newRole` or has a mutation in
    /// flight (debounce).
    ///
    /// - Returns: the error if the round-trip failed, `nil` on success / no-op.
    @discardableResult
    func changeRole(of member: OrgMember, to newRole: OrgRole) async -> Error? {
        guard !pendingOperations.contains(member.userId) else { return nil }
        guard let index = members.firstIndex(where: { $0.userId == member.userId }) else { return nil }
        guard members[index].role != newRole else { return nil }

        let snapshot = members
        pendingOperations.insert(member.userId)
        defer { pendingOperations.remove(member.userId) }

        // Optimistic: paint the new role immediately.
        members[index] = OrgMember(
            userId: member.userId,
            membershipId: member.membershipId,
            role: newRole,
            active: member.active,
            createdAt: member.createdAt
        )

        do {
            let updated = try await orgs.updateMember(
                in: orgId,
                userId: member.userId,
                role: newRole,
                active: nil
            )
            // Trust the server's authoritative return value, not the local copy.
            if let idx = members.firstIndex(where: { $0.userId == updated.userId }) {
                members[idx] = updated
            }
            actionError = nil
            return nil
        } catch {
            members = snapshot
            actionError = error
            return error
        }
    }

    // MARK: - Add member (optimistic)

    /// Adds a member by raw user id with a role. Validates the id client-side
    /// (a blank id is rejected before any service call). Optimistically
    /// inserts a provisional row, calls `addMember`, and on success replaces
    /// it with the server's authoritative membership. On failure, removes the
    /// provisional row and surfaces the error.
    ///
    /// NW-1 parallel: there is no handle→userId lookup endpoint, so add is by
    /// raw user id for v1 (see the report). A duplicate id is rejected
    /// client-side.
    ///
    /// - Returns: the error if rejected / failed, `nil` on success.
    @discardableResult
    func addMember(userId: String, role: OrgRole) async -> Error? {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = OrgMembersError.emptyUserId
            return OrgMembersError.emptyUserId
        }
        guard !members.contains(where: { $0.userId == trimmed }) else {
            actionError = OrgMembersError.alreadyMember
            return OrgMembersError.alreadyMember
        }
        guard !pendingOperations.contains(trimmed) else { return nil }

        let snapshot = members
        pendingOperations.insert(trimmed)
        defer { pendingOperations.remove(trimmed) }

        // Optimistic provisional row.
        let provisional = OrgMember(userId: trimmed, membershipId: nil, role: role, active: true, createdAt: nil)
        members.append(provisional)

        do {
            let created = try await orgs.addMember(to: orgId, userId: trimmed, role: role)
            // Replace the provisional row with the server's authoritative one.
            if let idx = members.firstIndex(where: { $0.userId == created.userId }) {
                members[idx] = created
            } else {
                members.append(created)
            }
            actionError = nil
            return nil
        } catch {
            members = snapshot
            actionError = error
            return error
        }
    }

    // MARK: - Remove member (optimistic)

    /// Removes a member. Optimistically drops the row, calls `removeMember`,
    /// and on failure restores the snapshot and surfaces the error.
    ///
    /// - Returns: the error if the round-trip failed, `nil` on success / no-op.
    @discardableResult
    func removeMember(_ member: OrgMember) async -> Error? {
        guard !pendingOperations.contains(member.userId) else { return nil }
        guard members.contains(where: { $0.userId == member.userId }) else { return nil }

        let snapshot = members
        pendingOperations.insert(member.userId)
        defer { pendingOperations.remove(member.userId) }

        members.removeAll { $0.userId == member.userId }

        do {
            try await orgs.removeMember(from: orgId, userId: member.userId)
            actionError = nil
            return nil
        } catch {
            members = snapshot
            actionError = error
            return error
        }
    }
}

// MARK: - OrgMembersError

/// Client-side member-management failures surfaced before any network call.
enum OrgMembersError: LocalizedError, Equatable {
    case emptyUserId
    case alreadyMember

    var errorDescription: String? {
        switch self {
        case .emptyUserId:
            return "Enter the user id of the person to add."
        case .alreadyMember:
            return "That user is already a member of this organization."
        }
    }
}
