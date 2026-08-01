import Foundation

// Wire models for the InterlinedList Documents & Sync API.
//
// Kept deliberately small and independent of the main app's `InterlinedKit`
// DTOs — this agent is a clean-room implementation. Fields the server sometimes
// omits (`content`, `contentHash`, `folderId`) are optional; decoders default
// them so a partial delta entry never fails to decode.

// MARK: - Documents

/// A document as returned by `GET /api/documents` and `GET /api/documents/{id}`.
public struct RemoteDocument: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// Full Markdown body. Present on detail/create/update; may be absent on
    /// list responses (which are metadata-only).
    public let content: String?
    public let folderId: String?
    public let updatedAt: Date
    public let createdAt: Date?
    public let isPublic: Bool?
    /// SHA-256 of the server content when the server computed it (advisory).
    public let contentHash: String?

    public init(
        id: String,
        title: String,
        content: String?,
        folderId: String?,
        updatedAt: Date,
        createdAt: Date? = nil,
        isPublic: Bool? = nil,
        contentHash: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.folderId = folderId
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.isPublic = isPublic
        self.contentHash = contentHash
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        content = try c.decodeIfPresent(String.self, forKey: .content)
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        // Fall back to createdAt, then epoch, so a metadata row never fails.
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = (try c.decodeIfPresent(Date.self, forKey: .updatedAt))
            ?? createdAt
            ?? Date(timeIntervalSince1970: 0)
        isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic)
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, folderId, updatedAt, createdAt, isPublic, contentHash
    }
}

/// A delta entry from `GET /api/documents/sync`. Same as `RemoteDocument` plus a
/// tombstone (`deletedAt`), which the live API populates inconsistently — the
/// engine also runs a periodic full-list reconciliation to catch deletions.
public struct DocumentDelta: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let content: String?
    public let folderId: String?
    public let updatedAt: Date
    public let deletedAt: Date?

    public var isDeleted: Bool { deletedAt != nil }

    public init(
        id: String,
        title: String,
        content: String?,
        folderId: String?,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.folderId = folderId
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        content = try c.decodeIfPresent(String.self, forKey: .content)
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        updatedAt = (try c.decodeIfPresent(Date.self, forKey: .updatedAt))
            ?? Date(timeIntervalSince1970: 0)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, folderId, updatedAt, deletedAt
    }
}

// MARK: - Folders

public struct RemoteFolder: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let parentId: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let deletedAt: Date?

    public var isDeleted: Bool { deletedAt != nil }

    public init(
        id: String,
        name: String,
        parentId: String?,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled Folder"
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, parentId, createdAt, updatedAt, deletedAt
    }
}

// MARK: - Response envelopes

/// `GET /api/documents/sync` response. Decode-only (aliased keys have no
/// matching stored property, so encoding is not synthesized).
public struct DeltaResponse: Decodable, Sendable, Equatable {
    public let lastSyncAt: Date?
    public let documents: [DocumentDelta]
    public let folders: [RemoteFolder]

    public init(lastSyncAt: Date?, documents: [DocumentDelta], folders: [RemoteFolder]) {
        self.lastSyncAt = lastSyncAt
        self.documents = documents
        self.folders = folders
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The server has used both `lastSyncAt` and `syncedAt` historically.
        lastSyncAt = (try? c.decodeIfPresent(Date.self, forKey: .lastSyncAt))
            ?? (try? c.decodeIfPresent(Date.self, forKey: .syncedAt))
            ?? nil
        documents = (try? c.decodeIfPresent([DocumentDelta].self, forKey: .documents)) ?? []
        folders = (try? c.decodeIfPresent([RemoteFolder].self, forKey: .folders)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case lastSyncAt, syncedAt, documents, folders
    }
}

/// `GET /api/documents` — the list envelope (`{ "documents": [...] }`).
public struct DocumentListResponse: Codable, Sendable, Equatable {
    public let documents: [RemoteDocument]
    public init(documents: [RemoteDocument]) { self.documents = documents }
}

/// `GET /api/documents/folders` — (`{ "folders": [...] }`).
public struct FolderListResponse: Codable, Sendable, Equatable {
    public let folders: [RemoteFolder]
    public init(folders: [RemoteFolder]) { self.folders = folders }
}

/// Create/update responses wrap the object: `{ "document": {...}, "message": "…" }`.
/// Some deployments return the bare object; ``DocumentEnvelope/document(in:)``
/// tolerates both.
public struct DocumentEnvelope: Codable, Sendable {
    public let document: RemoteDocument?
    public let message: String?
}

public struct FolderEnvelope: Codable, Sendable {
    public let folder: RemoteFolder?
    public let message: String?
}

/// `POST /api/auth/sync-token` response (fallback sign-in path only).
/// Decode-only (aliased keys have no matching stored property).
public struct SyncTokenResponse: Decodable, Sendable {
    public let token: String

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerate legacy field names.
        if let t = try? c.decodeIfPresent(String.self, forKey: .token), !t.isEmpty {
            token = t
        } else if let t = try? c.decodeIfPresent(String.self, forKey: .syncToken), !t.isEmpty {
            token = t
        } else if let t = try? c.decodeIfPresent(String.self, forKey: .accessToken), !t.isEmpty {
            token = t
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.token,
                .init(codingPath: decoder.codingPath, debugDescription: "No token field present")
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case token, syncToken, accessToken
    }
}

// MARK: - Request bodies

public struct CreateDocumentBody: Codable, Sendable, Equatable {
    public let title: String
    public let content: String
    public let folderId: String?
    public init(title: String, content: String, folderId: String? = nil) {
        self.title = title
        self.content = content
        self.folderId = folderId
    }
}

public struct UpdateDocumentBody: Codable, Sendable, Equatable {
    public let title: String?
    public let content: String?
    public let folderId: String?
    public init(title: String? = nil, content: String? = nil, folderId: String? = nil) {
        self.title = title
        self.content = content
        self.folderId = folderId
    }
}

public struct CreateFolderBody: Codable, Sendable, Equatable {
    public let name: String
    public let parentId: String?
    public init(name: String, parentId: String? = nil) {
        self.name = name
        self.parentId = parentId
    }
}

public struct SyncTokenRequest: Codable, Sendable, Equatable {
    public let email: String
    public let password: String
    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}
