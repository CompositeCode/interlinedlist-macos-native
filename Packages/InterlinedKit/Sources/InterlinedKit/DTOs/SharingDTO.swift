import Foundation

// MARK: - Sharing DTOs (the-gaps.md G3)
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
