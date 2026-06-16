import Foundation

// MARK: - OrganizationDTO

/// An organization. Fields modelled `1:1` against the API reference.
public struct OrganizationDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let isPublic: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        isPublic: Bool? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - OrganizationMemberDTO

/// A membership row from `GET /api/organizations/[id]/members`.
/// `role` is `"owner" | "admin" | "member"` (kept a free string at the kit
/// boundary; the Domain layer maps it to a typed role).
public struct OrganizationMemberDTO: Codable, Sendable, Equatable {
    public let userId: String
    public let role: String
    public let active: Bool?
    public let createdAt: Date?

    public init(
        userId: String,
        role: String,
        active: Bool? = nil,
        createdAt: Date? = nil
    ) {
        self.userId = userId
        self.role = role
        self.active = active
        self.createdAt = createdAt
    }
}

/// The membership object the server nests under `"membership"` on
/// `POST`/`PUT` member responses.
public struct OrganizationMembershipDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let organizationId: String
    public let role: String
    public let active: Bool?
    public let createdAt: Date?

    public init(
        id: String,
        userId: String,
        organizationId: String,
        role: String,
        active: Bool? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.organizationId = organizationId
        self.role = role
        self.active = active
        self.createdAt = createdAt
    }
}

/// `POST`/`PUT /api/organizations/[id]/members[/userId]` response envelope:
/// `{ "message": "…", "membership": { … } }`.
public struct OrganizationMembershipResponse: Codable, Sendable, Equatable {
    public let message: String?
    public let membership: OrganizationMembershipDTO

    public init(message: String? = nil, membership: OrganizationMembershipDTO) {
        self.message = message
        self.membership = membership
    }
}

// MARK: - OrganizationUserDTO

/// A user-with-role row from `GET /api/organizations/[id]/users`. Group-local,
/// tolerant shape (the canonical user model is owned by another group).
public struct OrganizationUserDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let role: String?

    public init(
        id: String,
        username: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        role: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.role = role
    }
}

// MARK: - Request bodies

/// `POST /api/organizations` body.
public struct CreateOrganizationRequest: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let isPublic: Bool

    public init(name: String, description: String, isPublic: Bool) {
        self.name = name
        self.description = description
        self.isPublic = isPublic
    }
}

/// `PATCH /api/organizations/[id]` body — partial update.
public struct UpdateOrganizationRequest: Codable, Sendable, Equatable {
    public let name: String?
    public let description: String?
    public let isPublic: Bool?

    public init(name: String? = nil, description: String? = nil, isPublic: Bool? = nil) {
        self.name = name
        self.description = description
        self.isPublic = isPublic
    }
}

/// `POST /api/organizations/[id]/members` body.
public struct AddOrganizationMemberRequest: Codable, Sendable, Equatable {
    public let userId: String
    public let role: String

    public init(userId: String, role: String) {
        self.userId = userId
        self.role = role
    }
}

/// `PUT /api/organizations/[id]/members/[userId]` body.
public struct UpdateOrganizationMemberRequest: Codable, Sendable, Equatable {
    public let role: String
    public let active: Bool?

    public init(role: String, active: Bool? = nil) {
        self.role = role
        self.active = active
    }
}
