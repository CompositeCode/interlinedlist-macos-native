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
    private let userService: UserServicing
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

    /// The user found by the most recent `lookupUser` call. Nil when no lookup
    /// has been run or when the handle returned 404. The add-by-handle UI reads
    /// this to show a confirmation row before calling `addMemberByHandle`.
    private(set) var foundUser: UserSearchResult?
    /// True while a handle lookup is in flight.
    private(set) var isLookingUp: Bool = false

    // MARK: - Init

    init(orgService: OrgServicing, userService: UserServicing, orgId: String) {
        self.orgs = orgService
        self.userService = userService
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

        // Last-owner protection (G25): demoting the only owner strands the
        // org. Rejected here so the user gets the specific sentence instead of
        // a generic 400 from the server.
        if let violation = OrgOwnershipRules.validateRoleChange(
            member: members[index],
            to: newRole,
            members: members
        ) {
            actionError = violation
            return violation
        }

        let snapshot = members
        pendingOperations.insert(member.userId)
        defer { pendingOperations.remove(member.userId) }

        // Optimistic: paint the new role immediately. Identity is carried
        // across explicitly — the roster row now renders a name and avatar,
        // and rebuilding without them would blank the row mid-flight.
        members[index] = OrgMember(
            userId: member.userId,
            membershipId: member.membershipId,
            role: newRole,
            active: member.active,
            createdAt: member.createdAt,
            username: member.username,
            displayName: member.displayName,
            avatarURL: member.avatarURL,
            emailVerified: member.emailVerified
        )

        do {
            let updated = try await orgs.updateMember(
                in: orgId,
                userId: member.userId,
                role: newRole,
                active: nil
            )
            // Trust the server's authoritative role, but keep the identity:
            // the membership envelope this returns carries no username or
            // avatar, so adopting it wholesale would blank the row.
            if let idx = members.firstIndex(where: { $0.userId == updated.userId }) {
                members[idx] = OrgMember(
                    userId: updated.userId,
                    membershipId: updated.membershipId,
                    role: updated.role,
                    active: updated.active,
                    createdAt: updated.createdAt ?? member.createdAt,
                    username: member.username,
                    displayName: member.displayName,
                    avatarURL: member.avatarURL,
                    emailVerified: member.emailVerified
                )
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

        // Last-owner protection (G25) — same rule as demotion.
        if let violation = OrgOwnershipRules.validateRemoval(member: member, members: members) {
            actionError = violation
            return violation
        }

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

    // MARK: - Suspend / restore (optimistic, work-consolidation.md G25)

    /// Suspends or restores a member's access without removing them from the
    /// organization (`/help/organizations` — "suspend their access").
    ///
    /// There is no suspend route: suspension is `active` on the member-update
    /// body, which is why this goes through `OrgServicing.setMemberSuspended`
    /// rather than a bespoke call. The service re-sends the member's current
    /// role so a suspend cannot silently change it.
    ///
    /// Optimistic, like every other mutation here: flip the row, call the
    /// service, replace with the server's authoritative membership on success,
    /// restore the snapshot on failure.
    ///
    /// - Returns: the error if rejected / failed, `nil` on success or no-op.
    @discardableResult
    func setSuspended(_ member: OrgMember, suspended: Bool) async -> Error? {
        guard !pendingOperations.contains(member.userId) else { return nil }
        guard let index = members.firstIndex(where: { $0.userId == member.userId }) else { return nil }
        guard members[index].isSuspended != suspended else { return nil }

        // Suspending the last owner leaves the org with no usable owner.
        if let violation = OrgOwnershipRules.validateSuspension(
            member: members[index],
            suspended: suspended,
            members: members
        ) {
            actionError = violation
            return violation
        }

        let snapshot = members
        pendingOperations.insert(member.userId)
        defer { pendingOperations.remove(member.userId) }

        // Optimistic: paint the new access state immediately.
        members[index] = OrgMember(
            userId: member.userId,
            membershipId: member.membershipId,
            role: member.role,
            active: !suspended,
            createdAt: member.createdAt,
            username: member.username,
            displayName: member.displayName,
            avatarURL: member.avatarURL,
            emailVerified: member.emailVerified
        )

        do {
            let updated = try await orgs.setMemberSuspended(
                in: orgId,
                member: member,
                suspended: suspended,
                members: snapshot
            )
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

    /// Whether the roster's rules currently allow suspending `member`. Drives
    /// the control's enabled state so the UI does not offer an action that is
    /// guaranteed to be rejected.
    func canSuspend(_ member: OrgMember) -> Bool {
        OrgOwnershipRules.validateSuspension(member: member, suspended: true, members: members) == nil
    }

    /// Whether the roster's rules currently allow removing `member`.
    func canRemove(_ member: OrgMember) -> Bool {
        OrgOwnershipRules.validateRemoval(member: member, members: members) == nil
    }

    /// Whether `member` can be moved to `role` under the last-owner rule.
    func canChangeRole(of member: OrgMember, to role: OrgRole) -> Bool {
        OrgOwnershipRules.validateRoleChange(member: member, to: role, members: members) == nil
    }

    // MARK: - Handle lookup (NW-6)

    /// Looks up a user by exact handle. Populates `foundUser` on success;
    /// sets `foundUser = nil` and surfaces the error / not-found state when the
    /// handle cannot be resolved.
    func lookupUser(handle: String) async {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = OrgMembersError.emptyHandle
            return
        }
        isLookingUp = true
        foundUser = nil
        actionError = nil
        defer { isLookingUp = false }
        do {
            let result = try await userService.lookupUser(handle: trimmed)
            if let result {
                foundUser = result
            } else {
                actionError = OrgMembersError.handleNotFound(trimmed)
            }
        } catch {
            actionError = error
        }
    }

    /// Chains `lookupUser` → `addMember` so the handle-based add UI only needs
    /// one call. On a successful lookup that finds a non-member, adds the member
    /// with the given role. Sets `actionError` if the handle resolves to nil,
    /// the user is already a member, or the add service call fails.
    @discardableResult
    func addMemberByHandle(handle: String, role: OrgRole) async -> Error? {
        await lookupUser(handle: handle)
        guard let user = foundUser else {
            return actionError
        }
        let result = await addMember(userId: user.id, role: role)
        if result == nil { foundUser = nil }
        return result
    }
}

// MARK: - OrgMembersError

/// Client-side member-management failures surfaced before any network call.
enum OrgMembersError: LocalizedError, Equatable {
    case emptyUserId
    case alreadyMember
    case emptyHandle
    case handleNotFound(String)

    var errorDescription: String? {
        switch self {
        case .emptyUserId:
            return "Enter the user id of the person to add."
        case .alreadyMember:
            return "That user is already a member of this organization."
        case .emptyHandle:
            return "Enter a @handle to look up."
        case .handleNotFound(let handle):
            return "@\(handle) was not found."
        }
    }
}
