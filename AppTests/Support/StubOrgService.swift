// StubOrgService
//
// Deterministic `OrgServicing` stub for App-layer view-model tests of the
// M6 Organizations feature. Mirrors the project's other stubs
// (`StubSocialService`, `StubNotificationsService`): an actor with one
// FIFO outcome queue per call site plus a recorded-call log so tests can
// assert intent (and assert *no* call was made on invalid input).
//
// Returns only `InterlinedDomain` values, so — unlike `StubSocialService`
// (which still surfaces the kit `FollowStatusDTO`) — this stub never
// imports `InterlinedKit`.

import Foundation
import InterlinedDomain

struct RecordedOrgCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case organizations(isPublic: Bool?, userId: String?, limit: Int, offset: Int)
        case create(name: String, description: String, isPublic: Bool)
        case organization(id: String)
        case update(id: String, name: String?, description: String?, isPublic: Bool?)
        case members(orgId: String, limit: Int, offset: Int)
        case addMember(orgId: String, userId: String, role: String)
        case updateMember(orgId: String, userId: String, role: String, active: Bool?)
        case removeMember(orgId: String, userId: String)
        case users(orgId: String)
    }
    let kind: Kind
}

actor StubOrgService: OrgServicing {

    // MARK: Outcome queues

    private var organizationsOutcomes: [Result<OrgsPage, Error>] = []
    private var createOutcomes: [Result<Organization, Error>] = []
    private var organizationOutcomes: [Result<Organization, Error>] = []
    private var updateOutcomes: [Result<Organization, Error>] = []
    private var membersOutcomes: [Result<OrgMembersPage, Error>] = []
    private var addMemberOutcomes: [Result<OrgMember, Error>] = []
    private var updateMemberOutcomes: [Result<OrgMember, Error>] = []
    private var removeMemberOutcomes: [Result<Void, Error>] = []
    private var usersOutcomes: [Result<[OrgUser], Error>] = []

    private(set) var recorded: [RecordedOrgCall] = []

    // MARK: Test programming

    func enqueueOrganizations(success page: OrgsPage) { organizationsOutcomes.append(.success(page)) }
    func enqueueOrganizations(failure error: Error) { organizationsOutcomes.append(.failure(error)) }

    func enqueueCreate(success org: Organization) { createOutcomes.append(.success(org)) }
    func enqueueCreate(failure error: Error) { createOutcomes.append(.failure(error)) }

    func enqueueOrganization(success org: Organization) { organizationOutcomes.append(.success(org)) }
    func enqueueOrganization(failure error: Error) { organizationOutcomes.append(.failure(error)) }

    func enqueueUpdate(success org: Organization) { updateOutcomes.append(.success(org)) }
    func enqueueUpdate(failure error: Error) { updateOutcomes.append(.failure(error)) }

    func enqueueMembers(success page: OrgMembersPage) { membersOutcomes.append(.success(page)) }
    func enqueueMembers(failure error: Error) { membersOutcomes.append(.failure(error)) }

    func enqueueAddMember(success member: OrgMember) { addMemberOutcomes.append(.success(member)) }
    func enqueueAddMember(failure error: Error) { addMemberOutcomes.append(.failure(error)) }

    func enqueueUpdateMember(success member: OrgMember) { updateMemberOutcomes.append(.success(member)) }
    func enqueueUpdateMember(failure error: Error) { updateMemberOutcomes.append(.failure(error)) }

    func enqueueRemoveMemberSuccess() { removeMemberOutcomes.append(.success(())) }
    func enqueueRemoveMember(failure error: Error) { removeMemberOutcomes.append(.failure(error)) }

    func enqueueUsers(success users: [OrgUser]) { usersOutcomes.append(.success(users)) }
    func enqueueUsers(failure error: Error) { usersOutcomes.append(.failure(error)) }

    // MARK: OrgServicing

    func organizations(
        isPublic: Bool?,
        userId: String?,
        limit: Int,
        offset: Int
    ) async throws -> OrgsPage {
        recorded.append(.init(kind: .organizations(isPublic: isPublic, userId: userId, limit: limit, offset: offset)))
        return try take(&organizationsOutcomes, label: "organizations")
    }

    func create(name: String, description: String, isPublic: Bool) async throws -> Organization {
        recorded.append(.init(kind: .create(name: name, description: description, isPublic: isPublic)))
        return try take(&createOutcomes, label: "create")
    }

    func organization(id: String) async throws -> Organization {
        recorded.append(.init(kind: .organization(id: id)))
        return try take(&organizationOutcomes, label: "organization")
    }

    func update(
        id: String,
        name: String?,
        description: String?,
        isPublic: Bool?
    ) async throws -> Organization {
        recorded.append(.init(kind: .update(id: id, name: name, description: description, isPublic: isPublic)))
        return try take(&updateOutcomes, label: "update")
    }

    func members(of orgId: String, limit: Int, offset: Int) async throws -> OrgMembersPage {
        recorded.append(.init(kind: .members(orgId: orgId, limit: limit, offset: offset)))
        return try take(&membersOutcomes, label: "members")
    }

    func addMember(to orgId: String, userId: String, role: OrgRole) async throws -> OrgMember {
        recorded.append(.init(kind: .addMember(orgId: orgId, userId: userId, role: role.wireToken)))
        return try take(&addMemberOutcomes, label: "addMember")
    }

    func updateMember(
        in orgId: String,
        userId: String,
        role: OrgRole,
        active: Bool?
    ) async throws -> OrgMember {
        recorded.append(.init(kind: .updateMember(orgId: orgId, userId: userId, role: role.wireToken, active: active)))
        return try take(&updateMemberOutcomes, label: "updateMember")
    }

    func removeMember(from orgId: String, userId: String) async throws {
        recorded.append(.init(kind: .removeMember(orgId: orgId, userId: userId)))
        let _: Void = try take(&removeMemberOutcomes, label: "removeMember")
    }

    func users(of orgId: String) async throws -> [OrgUser] {
        recorded.append(.init(kind: .users(orgId: orgId)))
        return try take(&usersOutcomes, label: "users")
    }

    // MARK: - Internals

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else {
            throw StubOrgError.noOutcome(label: label)
        }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubOrgError: Error, Equatable {
        case noOutcome(label: String)
    }
}
