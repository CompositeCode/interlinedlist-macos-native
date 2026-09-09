import Foundation

// MARK: - OrganizationDTO

/// An organization.
///
/// The core fields (`id` … `updatedAt`) come from every organization route.
/// Everything below `slug` is **membership context** the live collection
/// routes add and the older `1:1`-with-the-reference model omitted; all of it
/// is optional so a route that answers the lean shape still decodes.
///
/// VERIFIED live 2026-09-09 against `GET /api/organizations` and
/// `GET /api/user/organizations`, both of which answer rows like:
///
/// ```json
/// { "id": "fb29220f-…", "name": "Bikey Life", "slug": "bikey-life",
///   "description": "…", "avatar": null, "isPublic": true, "isSystem": false,
///   "settings": null, "createdAt": "…", "updatedAt": "…", "deletedAt": null,
///   "role": "member", "joinedAt": "…", "userRole": "member", "memberCount": 3 }
/// ```
///
/// `isSystem` is the flag that marks "The Public" — the org everyone
/// auto-joins and **nobody may leave** — so it has to survive the wire.
/// `role` / `userRole` are absent on rows the caller does not belong to (the
/// browse list returns those too), which is why both are optional.
public struct OrganizationDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let isPublic: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?

    /// URL-safe short name (`"bikey-life"`).
    public let slug: String?
    /// Org avatar URL. `null` for most orgs today.
    public let avatar: String?
    /// `true` for the system org ("The Public"). Absent on lean shapes.
    public let isSystem: Bool?
    /// Total members, when the route denormalizes the count onto the row.
    public let memberCount: Int?
    /// The caller's role in this org. Absent when the caller is not a member.
    public let role: String?
    /// Duplicate of `role` the server also emits. Kept so the client can fall
    /// back if only one of the two is present on a given route.
    public let userRole: String?
    /// When the caller joined. Absent when the caller is not a member.
    public let joinedAt: Date?
    /// Soft-delete tombstone. Non-nil means the org is deleted server-side.
    public let deletedAt: Date?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        isPublic: Bool? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        slug: String? = nil,
        avatar: String? = nil,
        isSystem: Bool? = nil,
        memberCount: Int? = nil,
        role: String? = nil,
        userRole: String? = nil,
        joinedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.slug = slug
        self.avatar = avatar
        self.isSystem = isSystem
        self.memberCount = memberCount
        self.role = role
        self.userRole = userRole
        self.joinedAt = joinedAt
        self.deletedAt = deletedAt
    }
}

// MARK: - OrganizationMemberDTO

/// A membership row from `GET /api/organizations/[id]/members`.
///
/// VERIFIED live 2026-09-09 — and the shape this shipped with could **never
/// decode it**. The live row is keyed by `id`, not `userId`, and dates the
/// membership with `joinedAt`, not `createdAt`:
///
/// ```json
/// { "id": "c65092fa-…", "username": "adron", "displayName": "Adron Hall",
///   "avatar": "https://…", "emailVerified": true,
///   "role": "owner", "active": true, "joinedAt": "2026-02-22T19:38:07.993Z" }
/// ```
///
/// The old model declared `userId: String` as non-optional, so every real
/// members response failed at the decoder with `keyNotFound(userId)` and the
/// roster never rendered — the same silent-decode-defect family as the
/// link-metadata G21 bug.
///
/// The row also carries the member's **identity** (username / display name /
/// avatar), which is why the roster needs no second per-user lookup.
///
/// Decoding is deliberately tolerant of both spellings: `id` **or** `userId`
/// for the user key, and `joinedAt` **or** `createdAt` for the timestamp. The
/// `/help/api/organizations` reference documents the `userId` spelling for the
/// membership envelope, so accepting both keeps one type usable for either
/// shape instead of failing closed on a server that changes its mind.
public struct OrganizationMemberDTO: Codable, Sendable, Equatable {

    /// The member user's id. Wire key is `id` on the live listing; `userId` is
    /// also accepted (the documented membership-envelope spelling).
    public let userId: String
    public let role: String
    public let active: Bool?
    /// When the membership was created. Wire key is `joinedAt` on the live
    /// listing; `createdAt` is also accepted.
    public let createdAt: Date?

    // Identity, denormalized onto the row by the live listing.
    public let username: String?
    public let displayName: String?
    public let avatar: String?
    public let emailVerified: Bool?

    public init(
        userId: String,
        role: String,
        active: Bool? = nil,
        createdAt: Date? = nil,
        username: String? = nil,
        displayName: String? = nil,
        avatar: String? = nil,
        emailVerified: Bool? = nil
    ) {
        self.userId = userId
        self.role = role
        self.active = active
        self.createdAt = createdAt
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.emailVerified = emailVerified
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, role, active, joinedAt, createdAt
        case username, displayName, avatar, emailVerified
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` is the live spelling; `userId` the documented one. Require one.
        if let id = try c.decodeIfPresent(String.self, forKey: .id) {
            userId = id
        } else {
            userId = try c.decode(String.self, forKey: .userId)
        }
        role = try c.decode(String.self, forKey: .role)
        active = try c.decodeIfPresent(Bool.self, forKey: .active)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .joinedAt)
            ?? c.decodeIfPresent(Date.self, forKey: .createdAt)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        emailVerified = try c.decodeIfPresent(Bool.self, forKey: .emailVerified)
    }

    /// Encodes with the live spellings (`id` / `joinedAt`) so a round-trip
    /// through this type reproduces what the server actually sends.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(active, forKey: .active)
        try c.encodeIfPresent(createdAt, forKey: .joinedAt)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(avatar, forKey: .avatar)
        try c.encodeIfPresent(emailVerified, forKey: .emailVerified)
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

/// Envelope returned by `POST /api/organizations` and
/// `PUT /api/organizations/[id]`.
///
/// VERIFIED live 2026-09-06: both write routes answer with
/// `{ "message": "Organization <created|updated> successfully",
///    "organization": { ... } }` — **not** a bare `OrganizationDTO`. The
/// builders previously decoded the bare DTO, so every organization create and
/// rename failed at the decoder even when the request itself succeeded
/// (work-consolidation.md §1c · V4).
public struct OrganizationWriteResponse: Codable, Sendable, Equatable {
    public let message: String?
    public let organization: OrganizationDTO

    public init(message: String? = nil, organization: OrganizationDTO) {
        self.message = message
        self.organization = organization
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

/// `POST /api/user/organizations` body — **join** an organization.
///
/// VERIFIED 2026-09-09 from two independent read-only sources, because the
/// route could not be exercised without a real write:
/// 1. the shipped web client's own organizations bundle, which joins with
///    `fetch("/api/user/organizations", { method: "POST", body:
///    JSON.stringify({ organizationId: e }) })`; and
/// 2. `GET /api/openapi.json`, whose `postUserOrganizations` operation
///    declares exactly one body property, `organizationId` (string), and a
///    201 response.
///
/// There is no `/api/organizations/{id}/join` route — that path 404s.
public struct JoinOrganizationRequest: Codable, Sendable, Equatable {
    public let organizationId: String

    public init(organizationId: String) {
        self.organizationId = organizationId
    }
}
