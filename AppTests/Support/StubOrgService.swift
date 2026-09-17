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
        // G25 lifecycle + org LinkedIn
        case delete(orgId: String, callerRole: String?)
        case leave(orgId: String, userId: String)
        case setMemberSuspended(orgId: String, userId: String, suspended: Bool)
        case linkedInStatus(orgId: String)
        case syncLinkedInPages(orgId: String, callerRole: String?)
        case assignLinkedInPage(orgId: String, userId: String, pageId: String?, callerRole: String?)
        case disconnectLinkedIn(orgId: String, callerRole: String?)
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
    private var deleteOutcomes: [Result<Void, Error>] = []
    private var leaveOutcomes: [Result<Void, Error>] = []
    private var setSuspendedOutcomes: [Result<OrgMember, Error>] = []
    private var linkedInStatusOutcomes: [Result<OrgLinkedInStatus, Error>] = []
    private var syncPagesOutcomes: [Result<OrgLinkedInStatus, Error>] = []
    private var assignPageOutcomes: [Result<Void, Error>] = []
    private var disconnectOutcomes: [Result<Void, Error>] = []

    /// What `linkedInAuthorizeURL` returns. Non-nil by default so the connect
    /// affordance is exercisable; set to nil to cover the unbuildable case.
    var authorizeURL: URL? = URL(string: "https://interlinedlist.com/api/auth/linkedin/org-authorize?organizationId=o1")

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

    func enqueueDeleteSuccess() { deleteOutcomes.append(.success(())) }
    func enqueueDelete(failure error: Error) { deleteOutcomes.append(.failure(error)) }

    func enqueueLeaveSuccess() { leaveOutcomes.append(.success(())) }
    func enqueueLeave(failure error: Error) { leaveOutcomes.append(.failure(error)) }

    func enqueueSetSuspended(success member: OrgMember) { setSuspendedOutcomes.append(.success(member)) }
    func enqueueSetSuspended(failure error: Error) { setSuspendedOutcomes.append(.failure(error)) }

    func enqueueLinkedInStatus(success status: OrgLinkedInStatus) { linkedInStatusOutcomes.append(.success(status)) }
    func enqueueLinkedInStatus(failure error: Error) { linkedInStatusOutcomes.append(.failure(error)) }

    func enqueueSyncPages(success status: OrgLinkedInStatus) { syncPagesOutcomes.append(.success(status)) }
    func enqueueSyncPages(failure error: Error) { syncPagesOutcomes.append(.failure(error)) }

    func enqueueAssignPageSuccess() { assignPageOutcomes.append(.success(())) }
    func enqueueAssignPage(failure error: Error) { assignPageOutcomes.append(.failure(error)) }

    func enqueueDisconnectSuccess() { disconnectOutcomes.append(.success(())) }
    func enqueueDisconnect(failure error: Error) { disconnectOutcomes.append(.failure(error)) }

    func setAuthorizeURL(_ url: URL?) { authorizeURL = url }

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

    // MARK: OrgServicing — G25 lifecycle

    func delete(id: String, callerRole: OrgRole?) async throws {
        recorded.append(.init(kind: .delete(orgId: id, callerRole: callerRole?.wireToken)))
        // Mirror the real service's precondition so view-model tests exercise
        // the same gate the production path applies.
        if let violation = OrgOwnershipRules.validateDelete(callerRole: callerRole) { throw violation }
        let _: Void = try take(&deleteOutcomes, label: "delete")
    }

    func leave(organization: Organization, userId: String, members: [OrgMember]) async throws {
        recorded.append(.init(kind: .leave(orgId: organization.id, userId: userId)))
        if let violation = OrgOwnershipRules.validateLeave(
            organization: organization,
            userId: userId,
            members: members
        ) { throw violation }
        let _: Void = try take(&leaveOutcomes, label: "leave")
    }

    func setMemberSuspended(
        in orgId: String,
        member: OrgMember,
        suspended: Bool,
        members: [OrgMember]
    ) async throws -> OrgMember {
        recorded.append(.init(kind: .setMemberSuspended(orgId: orgId, userId: member.userId, suspended: suspended)))
        if let violation = OrgOwnershipRules.validateSuspension(
            member: member,
            suspended: suspended,
            members: members
        ) { throw violation }
        return try take(&setSuspendedOutcomes, label: "setMemberSuspended")
    }

    // MARK: OrgServicing — G25 organization LinkedIn

    func linkedInStatus(of orgId: String) async throws -> OrgLinkedInStatus {
        recorded.append(.init(kind: .linkedInStatus(orgId: orgId)))
        return try take(&linkedInStatusOutcomes, label: "linkedInStatus")
    }

    func syncLinkedInPages(of orgId: String, callerRole: OrgRole?) async throws -> OrgLinkedInStatus {
        recorded.append(.init(kind: .syncLinkedInPages(orgId: orgId, callerRole: callerRole?.wireToken)))
        try requireManager(callerRole)
        return try take(&syncPagesOutcomes, label: "syncLinkedInPages")
    }

    func assignLinkedInPage(
        in orgId: String,
        userId: String,
        pageId: String?,
        callerRole: OrgRole?
    ) async throws {
        recorded.append(.init(kind: .assignLinkedInPage(
            orgId: orgId, userId: userId, pageId: pageId, callerRole: callerRole?.wireToken
        )))
        try requireManager(callerRole)
        let _: Void = try take(&assignPageOutcomes, label: "assignLinkedInPage")
    }

    func disconnectLinkedIn(from orgId: String, callerRole: OrgRole?) async throws {
        recorded.append(.init(kind: .disconnectLinkedIn(orgId: orgId, callerRole: callerRole?.wireToken)))
        try requireManager(callerRole)
        let _: Void = try take(&disconnectOutcomes, label: "disconnectLinkedIn")
    }

    nonisolated func linkedInAuthorizeURL(organizationId: String) -> URL? {
        URL(string: "https://interlinedlist.com/api/auth/linkedin/org-authorize?organizationId=\(organizationId)")
    }

    private func requireManager(_ role: OrgRole?) throws {
        switch role {
        case .owner, .admin: return
        case .member, .other, .none: throw OrgLifecycleError.linkedInRequiresOwnerOrAdmin
        }
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
