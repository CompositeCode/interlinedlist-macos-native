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
}

// MARK: - OrgService

public final class OrgService: OrgServicing {

    private let api: APIClientProtocol
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    ///   - decoder: shared kit JSON configuration, used to split the paginated
    ///     envelope. Defaults to the kit's `JSONCoders` decoder so dates parse
    ///     identically to the client.
    public init(
        api: APIClientProtocol,
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) {
        self.api = api
        self.decoder = decoder
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
        let dto = try await api.send(Organizations.create(body))
        return Organization(from: dto)
    }

    public func organization(id: String) async throws -> Organization {
        let dto = try await api.send(Organizations.get(id: id))
        return Organization(from: dto)
    }

    public func update(
        id: String,
        name: String?,
        description: String?,
        isPublic: Bool?
    ) async throws -> Organization {
        let body = UpdateOrganizationRequest(name: name, description: description, isPublic: isPublic)
        let dto = try await api.send(Organizations.update(id: id, body))
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
}
