import Foundation

// MARK: - DocumentDTO

/// A Markdown document. Fields modelled `1:1` against the API reference
/// (`https://interlinedlist.com/help/api`). Optional where a field is only
/// present on certain routes.
public struct DocumentDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// Markdown body. Absent on lightweight sync/list rows; present on detail
    /// and create/update responses.
    public let content: String?
    public let isPublic: Bool?
    public let folderId: String?
    public let relativePath: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    /// Sync-only tombstone flag (`GET /api/documents/sync` delta rows).
    public let deleted: Bool?

    public init(
        id: String,
        title: String,
        content: String? = nil,
        isPublic: Bool? = nil,
        folderId: String? = nil,
        relativePath: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deleted: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.isPublic = isPublic
        self.folderId = folderId
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

// MARK: - DocumentFolderDTO

/// A document folder. Supports nesting via `parentId`.
public struct DocumentFolderDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let parentId: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    /// Sync-only tombstone flag.
    public let deleted: Bool?

    public init(
        id: String,
        name: String,
        parentId: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deleted: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

// MARK: - Sync

/// `GET /api/documents/sync` response — the delta payload the
/// `DocumentSyncEngine` consumes. Folders and documents carry `deleted`
/// tombstones for rows removed since `lastSyncAt`.
public struct DocumentSyncResponse: Codable, Sendable, Equatable {
    public let syncedAt: Date?
    public let folders: [DocumentFolderDTO]
    public let documents: [DocumentDTO]

    public init(
        syncedAt: Date? = nil,
        folders: [DocumentFolderDTO] = [],
        documents: [DocumentDTO] = []
    ) {
        self.syncedAt = syncedAt
        self.folders = folders
        self.documents = documents
    }
}

/// A single batched local change pushed via `POST /api/documents/sync`.
/// `operation` is `"create" | "update" | "delete"`; `type` is
/// `"folder" | "document"`. The remaining fields are the changed payload,
/// modelled as a flexible map so the engine can serialize partial edits for
/// either entity without a fixed shape per combination.
public struct DocumentSyncOperation: Codable, Sendable, Equatable {
    public let operation: String
    public let type: String
    public let id: String?
    public let title: String?
    public let content: String?
    public let name: String?
    public let folderId: String?
    public let parentId: String?
    public let relativePath: String?
    public let isPublic: Bool?

    public init(
        operation: String,
        type: String,
        id: String? = nil,
        title: String? = nil,
        content: String? = nil,
        name: String? = nil,
        folderId: String? = nil,
        parentId: String? = nil,
        relativePath: String? = nil,
        isPublic: Bool? = nil
    ) {
        self.operation = operation
        self.type = type
        self.id = id
        self.title = title
        self.content = content
        self.name = name
        self.folderId = folderId
        self.parentId = parentId
        self.relativePath = relativePath
        self.isPublic = isPublic
    }
}

/// `POST /api/documents/sync` body: a batch of operations.
public struct DocumentSyncRequest: Codable, Sendable, Equatable {
    public let operations: [DocumentSyncOperation]

    public init(operations: [DocumentSyncOperation]) {
        self.operations = operations
    }
}

/// `POST /api/documents/sync` result. The server echoes per-operation results;
/// modelled tolerantly with the synced timestamp plus the resulting rows.
public struct DocumentSyncResultDTO: Codable, Sendable, Equatable {
    public let syncedAt: Date?
    public let folders: [DocumentFolderDTO]
    public let documents: [DocumentDTO]

    public init(
        syncedAt: Date? = nil,
        folders: [DocumentFolderDTO] = [],
        documents: [DocumentDTO] = []
    ) {
        self.syncedAt = syncedAt
        self.folders = folders
        self.documents = documents
    }
}

// MARK: - Image upload

/// `POST /api/documents/[id]/images/upload` response: `{ "url": "<href>" }`.
public struct DocumentImageUploadResponse: Codable, Sendable, Equatable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

// MARK: - Request bodies

/// `POST /api/documents` body.
public struct CreateDocumentRequest: Codable, Sendable, Equatable {
    public let title: String
    public let content: String
    public let folderId: String?
    public let relativePath: String?
    public let isPublic: Bool?

    public init(
        title: String,
        content: String,
        folderId: String? = nil,
        relativePath: String? = nil,
        isPublic: Bool? = nil
    ) {
        self.title = title
        self.content = content
        self.folderId = folderId
        self.relativePath = relativePath
        self.isPublic = isPublic
    }
}

/// `PATCH /api/documents/[id]` body — partial update.
public struct UpdateDocumentRequest: Codable, Sendable, Equatable {
    public let title: String?
    public let content: String?
    public let folderId: String?
    public let isPublic: Bool?

    public init(
        title: String? = nil,
        content: String? = nil,
        folderId: String? = nil,
        isPublic: Bool? = nil
    ) {
        self.title = title
        self.content = content
        self.folderId = folderId
        self.isPublic = isPublic
    }
}

/// `POST /api/documents/folders` body.
public struct CreateDocumentFolderRequest: Codable, Sendable, Equatable {
    public let name: String
    public let parentId: String?

    public init(name: String, parentId: String? = nil) {
        self.name = name
        self.parentId = parentId
    }
}

/// `PATCH /api/documents/folders/[id]` body — partial update.
public struct UpdateDocumentFolderRequest: Codable, Sendable, Equatable {
    public let name: String?
    public let parentId: String?

    public init(name: String? = nil, parentId: String? = nil) {
        self.name = name
        self.parentId = parentId
    }
}
