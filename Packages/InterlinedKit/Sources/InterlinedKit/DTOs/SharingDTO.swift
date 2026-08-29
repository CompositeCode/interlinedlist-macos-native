import Foundation

// MARK: - Sharing DTOs (work-consolidation.md G3)
//
// Tokenized share links for lists and documents. Shapes verified live
// 2026-07-31 (authorized create→capture→revoke on the test account's own list):
//
//   POST   /api/lists/{id}/share-links {role, expiresAt?}
//          -> { token, url, role, expiresAt }                                (201)
//   GET    /api/lists/{id}/share-links
//          -> { shareLinks: [{ token, role, expiresAt, createdAt, revokedAt, url }] }
//   GET    /api/lists/shared/{token}
//          -> { role, canClaim, needsAuth, list: { id, title, description, isPublic, updatedAt } }
//   DELETE /api/lists/{id}/share-links/{token} -> { revoked: true }
//   POST   /api/lists/shared/{token}           -> { listId, role }           (claim)
//
// The document endpoints mirror this with `document` in place of `list`.

/// A share link row (create response + list rows share this shape; `createdAt`
/// / `revokedAt` are present only on the list rows).
public struct ShareLinkDTO: Decodable, Sendable, Equatable {
    public let token: String
    public let url: String?
    public let role: String
    public let expiresAt: Date?
    public let createdAt: Date?
    public let revokedAt: Date?

    public init(
        token: String,
        url: String? = nil,
        role: String,
        expiresAt: Date? = nil,
        createdAt: Date? = nil,
        revokedAt: Date? = nil
    ) {
        self.token = token
        self.url = url
        self.role = role
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.revokedAt = revokedAt
    }
}

/// `GET /api/{lists,documents}/{id}/share-links` — `{ shareLinks: [...] }`.
public struct ShareLinksResponse: Decodable, Sendable, Equatable {
    public let shareLinks: [ShareLinkDTO]
    public init(shareLinks: [ShareLinkDTO]) { self.shareLinks = shareLinks }
}

/// Body for `POST /api/{lists,documents}/{id}/share-links`. `role` is one of
/// `watcher|collaborator|manager`; `expiresAt` omitted/nil means a permanent link.
public struct CreateShareLinkRequest: Encodable, Sendable, Equatable {
    public let role: String
    public let expiresAt: Date?
    public init(role: String, expiresAt: Date? = nil) {
        self.role = role
        self.expiresAt = expiresAt
    }
}

/// `DELETE …/share-links/{token}` — `{ revoked: true }`.
public struct RevokeShareResponse: Decodable, Sendable, Equatable {
    public let revoked: Bool?
    public init(revoked: Bool? = nil) { self.revoked = revoked }
}

// MARK: - Resolve

/// The list embedded in a resolved list-share.
public struct SharedListInfoDTO: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    public let isPublic: Bool?
    public let updatedAt: Date?

    public init(id: String, title: String, description: String? = nil, isPublic: Bool? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.isPublic = isPublic
        self.updatedAt = updatedAt
    }
}

/// `GET /api/lists/shared/{token}` — resolve a list share link.
public struct ResolvedListShareDTO: Decodable, Sendable, Equatable {
    public let role: String
    public let canClaim: Bool?
    public let needsAuth: Bool?
    public let list: SharedListInfoDTO?

    public init(role: String, canClaim: Bool? = nil, needsAuth: Bool? = nil, list: SharedListInfoDTO? = nil) {
        self.role = role
        self.canClaim = canClaim
        self.needsAuth = needsAuth
        self.list = list
    }
}

/// The document embedded in a resolved document-share.
public struct SharedDocumentInfoDTO: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let isPublic: Bool?
    public let updatedAt: Date?

    public init(id: String, title: String, isPublic: Bool? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.isPublic = isPublic
        self.updatedAt = updatedAt
    }
}

/// `GET /api/documents/shared/{token}` — resolve a document share link.
public struct ResolvedDocumentShareDTO: Decodable, Sendable, Equatable {
    public let role: String
    public let canClaim: Bool?
    public let needsAuth: Bool?
    public let document: SharedDocumentInfoDTO?

    public init(role: String, canClaim: Bool? = nil, needsAuth: Bool? = nil, document: SharedDocumentInfoDTO? = nil) {
        self.role = role
        self.canClaim = canClaim
        self.needsAuth = needsAuth
        self.document = document
    }
}

// MARK: - Claim

/// `POST /api/lists/shared/{token}` — claim a list share link.
public struct ClaimListShareResponse: Decodable, Sendable, Equatable {
    public let listId: String?
    public let role: String?
    public init(listId: String? = nil, role: String? = nil) {
        self.listId = listId
        self.role = role
    }
}

/// `POST /api/documents/shared/{token}` — claim a document share link.
public struct ClaimDocumentShareResponse: Decodable, Sendable, Equatable {
    public let documentId: String?
    public let role: String?
    public init(documentId: String? = nil, role: String? = nil) {
        self.documentId = documentId
        self.role = role
    }
}

// MARK: - Collaborators (G3 · document access & permissions)
//
// Per-person access grants on a document (the list equivalent is the existing
// watchers surface in `ListsEndpoint`). Roles are `watcher|collaborator|manager`.
//
//   GET    /api/documents/{id}/collaborators
//          -> { collaborators: [{ id, userId, role, createdAt, user:{…} }], pagination? }
//   POST   /api/documents/{id}/collaborators   { userId, role, notify }  -> { collaborating:true }|{ collaborator:{…} }
//   PUT    /api/documents/{id}/collaborators/{userId}  { role, notify }  -> { role }
//   DELETE /api/documents/{id}/collaborators/{userId}                    -> { removed:true }
//   GET    /api/documents/{id}/collaborators/users?search=…             -> { users:[…], total? }
//
// ⚠️ Two shapes differ between the web route handler and the shipping iOS
// client and were NOT re-probed live: (1) the collaborator row — the server
// nests the user under `user:{…}` while iOS decodes flat `username/displayName/
// avatar`; this DTO tolerates BOTH (all optional). (2) the search query param —
// the server uses `search`, iOS uses `q`; the builder sends both. Confirm via a
// live ContractTests pass before relying on either.

/// The user embedded in a collaborator row or surfaced by the candidate search.
public struct CollaboratorUserDTO: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let email: String?
    public let avatar: String?

    public init(id: String, username: String? = nil, displayName: String? = nil, email: String? = nil, avatar: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.avatar = avatar
    }
}

/// A per-person document collaborator. Tolerates the nested `user` object (web
/// route handler) and flat `username/displayName/avatar` fields (iOS) — both
/// optional, mapped in the domain layer.
public struct CollaboratorDTO: Decodable, Sendable, Equatable {
    public let id: String?
    public let userId: String
    public let role: String
    public let createdAt: Date?
    public let user: CollaboratorUserDTO?
    public let username: String?
    public let displayName: String?
    public let avatar: String?

    public init(
        id: String? = nil,
        userId: String,
        role: String,
        createdAt: Date? = nil,
        user: CollaboratorUserDTO? = nil,
        username: String? = nil,
        displayName: String? = nil,
        avatar: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.role = role
        self.createdAt = createdAt
        self.user = user
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
    }
}

/// `GET …/collaborators` — `{ collaborators: [...] }`. Any `pagination` envelope
/// key is ignored (the sharing UI lists all collaborators at once).
public struct CollaboratorsResponse: Decodable, Sendable, Equatable {
    public let collaborators: [CollaboratorDTO]
    public init(collaborators: [CollaboratorDTO]) {
        self.collaborators = collaborators
    }
}

/// Body for `POST …/collaborators`. `notify` sends the "Email this person" invite.
public struct AddCollaboratorRequest: Encodable, Sendable, Equatable {
    public let userId: String
    public let role: String
    public let notify: Bool
    public init(userId: String, role: String, notify: Bool) {
        self.userId = userId
        self.role = role
        self.notify = notify
    }
}

/// `POST …/collaborators` — tolerant of `{ collaborating:true }` (web) and
/// `{ collaborator:{…} }` (iOS). Either signals success.
public struct AddCollaboratorResponse: Decodable, Sendable, Equatable {
    public let collaborating: Bool?
    public let collaborator: CollaboratorDTO?
    public init(collaborating: Bool? = nil, collaborator: CollaboratorDTO? = nil) {
        self.collaborating = collaborating
        self.collaborator = collaborator
    }
}

/// Body for `PUT …/collaborators/{userId}`.
public struct SetCollaboratorRoleRequest: Encodable, Sendable, Equatable {
    public let role: String
    public let notify: Bool
    public init(role: String, notify: Bool) {
        self.role = role
        self.notify = notify
    }
}

/// `PUT …/collaborators/{userId}` — `{ role }`.
public struct SetRoleResponse: Decodable, Sendable, Equatable {
    public let role: String?
    public init(role: String? = nil) { self.role = role }
}

/// `DELETE …/collaborators/{userId}` — `{ removed:true }`.
public struct RemoveCollaboratorResponse: Decodable, Sendable, Equatable {
    public let removed: Bool?
    public init(removed: Bool? = nil) { self.removed = removed }
}

/// `GET …/collaborators/users?search=…` — `{ users:[…], total? }`.
public struct CollaboratorCandidatesResponse: Decodable, Sendable, Equatable {
    public let users: [CollaboratorUserDTO]
    public let total: Int?
    public init(users: [CollaboratorUserDTO], total: Int? = nil) {
        self.users = users
        self.total = total
    }
}

// MARK: - Email invites (G3 · invite by email + pending invites)
//
// Tokenized email invites for lists and documents. Same shape on both resources.
//
//   GET    /api/{lists,documents}/{id}/invites
//          -> { invites: [{ token, email, role, expiresAt, accepted, createdAt }] }
//   POST   /api/{lists,documents}/{id}/invites  { email, role, expiresAt? }
//          -> { email, role, expiresAt, url }                                  (201)
//   DELETE /api/{lists,documents}/{id}/invites/{token} -> { revoked:true }
//
// Create is subscriber-gated + rate-limited (30/hr); revoke is not (a downgraded
// owner must still be able to revoke access they granted).

/// A pending or accepted email invite.
public struct ShareInviteDTO: Decodable, Sendable, Equatable {
    public let token: String
    public let email: String
    public let role: String
    public let expiresAt: Date?
    public let accepted: Bool?
    public let createdAt: Date?

    public init(token: String, email: String, role: String, expiresAt: Date? = nil, accepted: Bool? = nil, createdAt: Date? = nil) {
        self.token = token
        self.email = email
        self.role = role
        self.expiresAt = expiresAt
        self.accepted = accepted
        self.createdAt = createdAt
    }
}

/// `GET …/invites` — `{ invites: [...] }`.
public struct ShareInvitesResponse: Decodable, Sendable, Equatable {
    public let invites: [ShareInviteDTO]
    public init(invites: [ShareInviteDTO]) { self.invites = invites }
}

/// Body for `POST …/invites`. `expiresAt` nil means a permanent invite.
public struct CreateInviteRequest: Encodable, Sendable, Equatable {
    public let email: String
    public let role: String
    public let expiresAt: Date?
    public init(email: String, role: String, expiresAt: Date? = nil) {
        self.email = email
        self.role = role
        self.expiresAt = expiresAt
    }
}

/// `POST …/invites` — `{ email, role, expiresAt, url }` (201).
public struct CreateInviteResponse: Decodable, Sendable, Equatable {
    public let email: String
    public let role: String
    public let expiresAt: Date?
    public let url: String?
    public init(email: String, role: String, expiresAt: Date? = nil, url: String? = nil) {
        self.email = email
        self.role = role
        self.expiresAt = expiresAt
        self.url = url
    }
}
