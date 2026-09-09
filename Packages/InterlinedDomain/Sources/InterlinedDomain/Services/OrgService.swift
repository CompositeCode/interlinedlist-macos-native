import Foundation
import InterlinedKit

// MARK: - OrgServicing

/// The organizations surface the App layer codes against (PLAN.md §1
/// "Organizations", §6 M6 — "organizations + member roles"). Covers all nine
/// Organizations endpoints: list, create, get, patch, members (list / add),
/// member-role PUT, member DELETE, and the users-with-roles listing.
///
/// Follows the same DI shape as the other domain services — takes its
/// `APIClientProtocol` (and the shared decoder for the paginated-envelope
/// split) as parameters so unit tests run against a stub. Per decision 0003
/// every method returns domain values (`Organization` / `OrgMember` /
/// `OrgUser`); the kit DTOs never cross the seam.
public protocol OrgServicing: Sendable {

    // MARK: - Org CRUD

    /// Loads one page of organizations. `isPublic` / `userId` are optional
    /// server-side filters; `nil` leaves them off the wire.
    func organizations(
        isPublic: Bool?,
        userId: String?,
        limit: Int,
        offset: Int
    ) async throws -> OrgsPage

    /// Creates an organization. `name` / `description` / `isPublic` map
    /// directly onto the create body.
    func create(name: String, description: String, isPublic: Bool) async throws -> Organization

    /// Loads a single organization by id.
    func organization(id: String) async throws -> Organization

    /// Patches an organization. Every field is optional — only the non-nil
    /// fields are sent, so the caller patches just what changed.
    func update(
        id: String,
        name: String?,
        description: String?,
        isPublic: Bool?
    ) async throws -> Organization

    // MARK: - Members

    /// Loads one page of an org's members (keyed by user, no membership-record
    /// id on this shape).
    func members(of orgId: String, limit: Int, offset: Int) async throws -> OrgMembersPage

    /// Adds a member to an org with a role. Returns the created membership
    /// (which carries the membership-record id from the response envelope).
    func addMember(to orgId: String, userId: String, role: OrgRole) async throws -> OrgMember

    /// Updates a member's role (and optionally their active flag). Mirrors the
    /// `PUT /api/organizations/[id]/members/[userId]` builder.
    func updateMember(
        in orgId: String,
        userId: String,
        role: OrgRole,
        active: Bool?
    ) async throws -> OrgMember

    /// Removes a member from an org.
    func removeMember(from orgId: String, userId: String) async throws

    // MARK: - Users with roles

    /// Loads the org's users with their roles — a roster the member-management
    /// UI renders without a second per-user lookup. Bare-array shape today
    /// (no pagination on this endpoint).
    func users(of orgId: String) async throws -> [OrgUser]

    // MARK: - Lifecycle (work-consolidation.md G25)

    /// Deletes an organization. Owner-only and **not reversible** — the caller
    /// is responsible for confirming with the user first.
    ///
    /// `callerRole` is checked client-side so a non-owner gets
    /// `OrgLifecycleError.onlyOwnerCanDelete` instead of a bare 403. Pass the
    /// role the membership list reported; `nil` means "unknown", which is
    /// treated as not-an-owner.
    func delete(id: String, callerRole: OrgRole?) async throws

    /// Leaves an organization.
    ///
    /// There is no `/leave` route — leaving is removing *yourself* from the
    /// members collection, exactly as the web client does it. The system-org
    /// and last-owner rules are enforced before the call; pass the roster in
    /// `members` when it is loaded so the last-owner rule can apply, or `[]`
    /// to let the server be the only backstop.
    func leave(
        organization: Organization,
        userId: String,
        members: [OrgMember]
    ) async throws

    /// Suspends or restores a member's access without removing them from the
    /// org. Sends the member's **existing** role alongside the new `active`
    /// flag, because the update body requires a role and re-sending the current
    /// one is what keeps a suspend from silently changing it.
    ///
    /// Refuses to suspend the last owner.
    func setMemberSuspended(
        in orgId: String,
        member: OrgMember,
        suspended: Bool,
        members: [OrgMember]
    ) async throws -> OrgMember

    // MARK: - Organization LinkedIn (work-consolidation.md G25)

    /// Reads the org's shared-LinkedIn state: connection, discovered company
    /// pages, and current assignments. The only readable route of the four.
    func linkedInStatus(of orgId: String) async throws -> OrgLinkedInStatus

    /// Re-discovers the org's LinkedIn company pages and returns the refreshed
    /// status.
    ///
    /// The sync response body is unmodelled upstream, so the implementation
    /// ignores it and re-reads `linkedInStatus`. That also means a *successful*
    /// sync whose follow-up read fails still throws — callers that want to keep
    /// showing the stale page list should catch and keep their previous value.
    func syncLinkedInPages(of orgId: String, callerRole: OrgRole?) async throws -> OrgLinkedInStatus

    /// Assigns one member to one company page, or clears their assignment with
    /// a `nil` `pageId`. Owner/admin only.
    func assignLinkedInPage(
        in orgId: String,
        userId: String,
        pageId: String?,
        callerRole: OrgRole?
    ) async throws

    /// Disconnects the org's shared LinkedIn credential.
    ///
    /// Destructive beyond the org itself: every assigned member silently falls
    /// back to their personal LinkedIn identity. Owner/admin only.
    func disconnectLinkedIn(from orgId: String, callerRole: OrgRole?) async throws

    /// The browser URL that starts the org's LinkedIn OAuth flow.
    ///
    /// `GET /api/auth/linkedin/org-authorize?organizationId=…` is a redirect
    /// flow (`x-auth-type: none`), so the App opens it rather than calling it —
    /// the same handoff `UserServicing.identityLinkURL` uses for personal
    /// identity linking. Building it here keeps the App layer free of any URL
    /// knowledge (decision 0003).
    func linkedInAuthorizeURL(organizationId: String) -> URL?
}

// MARK: - OrgService

public final class OrgService: OrgServicing {

    private let api: APIClientProtocol
    private let decoder: JSONDecoder
    private let baseURL: URL

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    ///   - decoder: shared kit JSON configuration, used to split the paginated
    ///     envelope. Defaults to the kit's `JSONCoders` decoder so dates parse
    ///     identically to the client.
    ///   - baseURL: origin for the browser-redirect OAuth URL. Mirrors
    ///     `UserService`'s parameter of the same name.
    public init(
        api: APIClientProtocol,
        decoder: JSONDecoder = JSONCoders.makeDecoder(),
        baseURL: URL = URL(string: "https://interlinedlist.com")!
    ) {
        self.api = api
        self.decoder = decoder
        self.baseURL = baseURL
    }

    // MARK: Org CRUD

    public func organizations(
        isPublic: Bool?,
        userId: String?,
        limit: Int,
        offset: Int
    ) async throws -> OrgsPage {
        let request = Organizations.list(
            isPublic: isPublic,
            userId: userId,
            limit: limit,
            offset: offset
        )
        let (data, _) = try await api.sendRaw(request)
        guard let key = request.paginationKey else {
            throw APIError.decoding(
                type: "Paginated<OrganizationDTO>",
                message: "Organizations.list missing paginationKey"
            )
        }
        let paginated = try PaginatedDecoder.decode(
            OrganizationDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        return OrgsPage(from: paginated)
    }

    public func create(
        name: String,
        description: String,
        isPublic: Bool
    ) async throws -> Organization {
        let body = CreateOrganizationRequest(name: name, description: description, isPublic: isPublic)
        // The live create answers `{ message, organization }`; unwrap it.
        let dto = try await api.send(Organizations.create(body)).organization
        return Organization(from: dto)
    }

    public func organization(id: String) async throws -> Organization {
        // The live read answers `{ organization }`; unwrap it.
        let dto = try await api.send(Organizations.get(id: id)).organization
        return Organization(from: dto)
    }

    public func update(
        id: String,
        name: String?,
        description: String?,
        isPublic: Bool?
    ) async throws -> Organization {
        let body = UpdateOrganizationRequest(name: name, description: description, isPublic: isPublic)
        // The live update answers `{ message, organization }`; unwrap it.
        let dto = try await api.send(Organizations.update(id: id, body)).organization
        return Organization(from: dto)
    }

    // MARK: Members

    public func members(
        of orgId: String,
        limit: Int,
        offset: Int
    ) async throws -> OrgMembersPage {
        let request = Organizations.members(id: orgId, limit: limit, offset: offset)
        let (data, _) = try await api.sendRaw(request)
        guard let key = request.paginationKey else {
            throw APIError.decoding(
                type: "Paginated<OrganizationMemberDTO>",
                message: "Organizations.members missing paginationKey"
            )
        }
        let paginated = try PaginatedDecoder.decode(
            OrganizationMemberDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        return OrgMembersPage(from: paginated)
    }

    public func addMember(
        to orgId: String,
        userId: String,
        role: OrgRole
    ) async throws -> OrgMember {
        let body = AddOrganizationMemberRequest(userId: userId, role: role.wireToken)
        let response = try await api.send(Organizations.addMember(id: orgId, body))
        return OrgMember(from: response.membership)
    }

    public func updateMember(
        in orgId: String,
        userId: String,
        role: OrgRole,
        active: Bool?
    ) async throws -> OrgMember {
        let body = UpdateOrganizationMemberRequest(role: role.wireToken, active: active)
        let response = try await api.send(Organizations.updateMember(id: orgId, userId: userId, body))
        return OrgMember(from: response.membership)
    }

    public func removeMember(from orgId: String, userId: String) async throws {
        try await api.sendVoid(Organizations.removeMember(id: orgId, userId: userId))
    }

    // MARK: Users with roles

    public func users(of orgId: String) async throws -> [OrgUser] {
        let dtos = try await api.send(Organizations.users(id: orgId))
        return dtos.map(OrgUser.init(from:))
    }

    // MARK: Lifecycle (work-consolidation.md G25)

    public func delete(id: String, callerRole: OrgRole?) async throws {
        if let violation = OrgOwnershipRules.validateDelete(callerRole: callerRole) {
            throw violation
        }
        // Response body is unmodelled upstream; only the status matters.
        try await api.sendVoid(Organizations.delete(id: id))
    }

    public func leave(
        organization: Organization,
        userId: String,
        members: [OrgMember]
    ) async throws {
        guard !userId.isEmpty else { throw OrgLifecycleError.unknownCurrentUser }
        if let violation = OrgOwnershipRules.validateLeave(
            organization: organization,
            userId: userId,
            members: members
        ) {
            throw violation
        }
        // Leaving is removing yourself — there is no dedicated /leave route.
        try await api.sendVoid(
            Organizations.removeMember(id: organization.id, userId: userId)
        )
    }

    public func setMemberSuspended(
        in orgId: String,
        member: OrgMember,
        suspended: Bool,
        members: [OrgMember]
    ) async throws -> OrgMember {
        if let violation = OrgOwnershipRules.validateSuspension(
            member: member,
            suspended: suspended,
            members: members
        ) {
            throw violation
        }
        // Re-send the member's current role: the update body requires one, and
        // omitting it would let the server reinterpret the role on a suspend.
        let body = UpdateOrganizationMemberRequest(
            role: member.role.wireToken,
            active: !suspended
        )
        let response = try await api.send(
            Organizations.updateMember(id: orgId, userId: member.userId, body)
        )
        let updated = OrgMember(from: response.membership)
        // The membership envelope drops the identity fields the roster row
        // carries, so fold them back in rather than blanking the row.
        return OrgMember(
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

    // MARK: Organization LinkedIn (work-consolidation.md G25)

    public func linkedInStatus(of orgId: String) async throws -> OrgLinkedInStatus {
        OrgLinkedInStatus(from: try await api.send(Organizations.linkedInStatus(id: orgId)))
    }

    public func syncLinkedInPages(
        of orgId: String,
        callerRole: OrgRole?
    ) async throws -> OrgLinkedInStatus {
        try requireLinkedInManager(callerRole)
        // The 201 body is unmodelled upstream — ignore it and re-read status,
        // which is the only route that returns the discovered pages.
        try await api.sendVoid(Organizations.syncLinkedInPages(id: orgId))
        return try await linkedInStatus(of: orgId)
    }

    public func assignLinkedInPage(
        in orgId: String,
        userId: String,
        pageId: String?,
        callerRole: OrgRole?
    ) async throws {
        try requireLinkedInManager(callerRole)
        guard !userId.isEmpty else { throw OrgLifecycleError.unknownCurrentUser }
        let body = UpdateOrgLinkedInAssignmentRequest(userId: userId, pageId: pageId)
        try await api.sendVoid(Organizations.assignLinkedInPage(id: orgId, body))
    }

    public func disconnectLinkedIn(from orgId: String, callerRole: OrgRole?) async throws {
        try requireLinkedInManager(callerRole)
        try await api.sendVoid(Organizations.disconnectLinkedIn(id: orgId))
    }

    public func linkedInAuthorizeURL(organizationId: String) -> URL? {
        OrgLinkedInAuthorization.url(baseURL: baseURL, organizationId: organizationId)
    }

    /// Owner/admin gate shared by the three org-LinkedIn writes.
    private func requireLinkedInManager(_ role: OrgRole?) throws {
        switch role {
        case .owner, .admin: return
        case .member, .other, .none: throw OrgLifecycleError.linkedInRequiresOwnerOrAdmin
        }
    }
}

