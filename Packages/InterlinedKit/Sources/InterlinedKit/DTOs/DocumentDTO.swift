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

/// Envelope returned by `POST /api/documents`, `GET /api/documents/[id]`,
/// `PATCH /api/documents/[id]` and `PUT /api/documents/[id]`.
///
/// VERIFIED live 2026-09-06: all four answer `{ "message"?: …,
/// "document": { ... } }` — **not** a bare `DocumentDTO`. The builders
/// previously decoded the bare DTO, so opening, creating and saving a document
/// each failed at the decoder. Found while probing G27's `PUT` variant; it is
/// the same envelope defect as the folder routes (§1c · V5).
public struct DocumentResponse: Codable, Sendable, Equatable {
    public let message: String?
    public let document: DocumentDTO

    public init(message: String? = nil, document: DocumentDTO) {
        self.message = message
        self.document = document
    }
}

/// Envelope returned by `POST /api/documents/folders`,
/// `GET /api/documents/folders/[id]` and `PUT /api/documents/folders/[id]`.
///
/// VERIFIED live 2026-09-06: all three answer `{ "message"?: …,
/// "folder": { ... } }` — **not** a bare `DocumentFolderDTO`. The builders
/// previously decoded the bare DTO, so folder create, read and rename all
/// failed at the decoder (work-consolidation.md §1c · V5).
public struct DocumentFolderResponse: Codable, Sendable, Equatable {
    public let message: String?
    public let folder: DocumentFolderDTO

    public init(message: String? = nil, folder: DocumentFolderDTO) {
        self.message = message
        self.folder = folder
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

// MARK: - Sidebar tree (work-consolidation.md G24)

/// One folder row inside `GET /api/documents/tree`.
///
/// VERIFIED live 2026-09-09 (read-only Bearer probe). The tree is **flat in
/// its folders and nested in its documents**: every folder in the account
/// appears once at the top level of `folders`, nesting is expressed by
/// `parentId` (exactly like `DocumentFolderDTO`), and each folder carries its
/// own documents inline under `documents`. Do not look for a nested `folders`
/// array — there isn't one.
///
/// The inline document rows are **lighter than `GET /api/documents` rows**:
/// only `id`, `title`, `relativePath` and `isPublic` are present. There is no
/// `content`, no `createdAt` / `updatedAt`, and no `folderId` (the enclosing
/// folder *is* the folder id). That is why the tree replaces the sidebar's
/// folder fetch but cannot replace the document list's own fetch — see
/// `DocumentTreeResponse`.
public struct DocumentTreeFolderDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let parentId: String?
    /// Documents filed directly in this folder. Defaulted to `[]` rather than
    /// required: an empty folder answers `"documents":[]` today, but a future
    /// slimmer variant that omits the key entirely must not fail the decode.
    public let documents: [DocumentDTO]

    public init(
        id: String,
        name: String,
        parentId: String? = nil,
        documents: [DocumentDTO] = []
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.documents = documents
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, parentId, documents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        self.documents = try c.decodeIfPresent([DocumentDTO].self, forKey: .documents) ?? []
    }
}

/// `GET /api/documents/tree` — the whole sidebar in one call.
///
/// VERIFIED live 2026-09-09 (read-only Bearer probe against the `.env` test
/// account). `OPTIONS` reports `Allow: GET, HEAD, OPTIONS`; the live body is:
///
/// ```json
/// {"folders":[{"id":"2b77…","name":"One-Folder","parentId":null,
///              "documents":[{"id":"effb…","title":"a-single-doc",
///                            "relativePath":"a-single-doc.md","isPublic":false}]},
///             {"id":"3775…","name":"emptiness","parentId":null,"documents":[]}],
///  "rootDocuments":[{"id":"6066…","title":"a-root-doc",
///                    "relativePath":"a-root-doc.md","isPublic":false}]}
/// ```
///
/// Two things the shape forces on consumers:
///
/// 1. **Root documents are a sibling array, not a synthetic folder.** Do not
///    flatten `rootDocuments` into `folders` — "no folder" is a distinct
///    destination the UI has to be able to name.
/// 2. **The `_templates` folder is returned inline** alongside real folders
///    (it is the same folder the template picker seeds). Anything offering
///    folders as a user-facing destination has to filter it out.
public struct DocumentTreeResponse: Codable, Sendable, Equatable {
    public let folders: [DocumentTreeFolderDTO]
    /// Documents with no folder. A sibling of `folders`, never nested in it.
    public let rootDocuments: [DocumentDTO]

    public init(
        folders: [DocumentTreeFolderDTO] = [],
        rootDocuments: [DocumentDTO] = []
    ) {
        self.folders = folders
        self.rootDocuments = rootDocuments
    }

    private enum CodingKeys: String, CodingKey {
        case folders, rootDocuments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Both keys defaulted: an account with no folders at all still has to
        // decode, and the sidebar treats "absent" and "empty" identically.
        self.folders = try c.decodeIfPresent([DocumentTreeFolderDTO].self, forKey: .folders) ?? []
        self.rootDocuments = try c.decodeIfPresent([DocumentDTO].self, forKey: .rootDocuments) ?? []
    }
}

// MARK: - Public documents by user

/// `GET /api/users/{username}/documents` — a user's *public* documents.
///
/// VERIFIED live 2026-09-09: `x-auth-type: none` in the live OpenAPI spec, and
/// the route answered identically with and without an `Authorization` header,
/// so the builder sends `.none`. The live body:
///
/// ```json
/// {"documents":[{"id":"0260…","title":"Railroad Apps to Build for Fun",
///                "folderId":null,"relativePath":"railroad-passenger-seating.md",
///                "createdAt":"…","updatedAt":"…"}],
///  "folders":[]}
/// ```
///
/// Unlike the tree's inline rows these carry `folderId`, `createdAt` and
/// `updatedAt` (but still no `content` — fetch the document to read it).
///
/// `folders` was empty on every account reachable read-only, so its non-empty
/// shape is **unverified**. It is typed as `DocumentTreeFolderDTO`, whose
/// `documents` array is optional-with-default, so it decodes whether the
/// server sends plain folder rows or folder rows with documents nested.
public struct PublicUserDocumentsResponse: Codable, Sendable, Equatable {
    public let documents: [DocumentDTO]
    public let folders: [DocumentTreeFolderDTO]

    public init(
        documents: [DocumentDTO] = [],
        folders: [DocumentTreeFolderDTO] = []
    ) {
        self.documents = documents
        self.folders = folders
    }

    private enum CodingKeys: String, CodingKey {
        case documents, folders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.documents = try c.decodeIfPresent([DocumentDTO].self, forKey: .documents) ?? []
        self.folders = try c.decodeIfPresent([DocumentTreeFolderDTO].self, forKey: .folders) ?? []
    }
}

// MARK: - Invite landing

/// `GET /api/documents/invite/{token}` — the invite landing payload.
///
/// Shape per the live `/help/api/sharing` reference; the 404 branch was
/// verified live 2026-09-09 (`{"error":"Invite not found, expired, or
/// revoked","code":"not_found"}` for an unknown token, unauthenticated).
/// The success branch could not be exercised read-only — minting an invite is
/// a write, and the shared test account is off-limits for writes — so every
/// field except `role` is optional and the decode is tolerant.
///
/// The response deliberately never returns the invited email address: it
/// reveals only enough to pick the right branch of the landing page.
///
/// Note the pairing: `GET` here is public, but `POST /api/documents/invite/
/// {token}` (the *accept*) is `x-auth-type: session` — a Bearer-only client
/// cannot claim. See `Documents.invite(token:)`.
public struct DocumentInviteLandingDTO: Codable, Sendable, Equatable {
    /// The role the invite grants (`watcher` / `collaborator` / `manager`).
    public let role: String
    /// `true` when nobody is signed in → prompt to sign in or create an account.
    public let needsAuth: Bool?
    /// `true` when the signed-in user's verified email matches the invited
    /// address, so they may `POST` to claim.
    public let canClaim: Bool?
    /// `true` when someone *is* signed in but under a different address.
    public let wrongAccount: Bool?
    /// `true` when the invite was already claimed. It still resolves, so the
    /// landing page can link the claimer into the document.
    public let accepted: Bool?
    /// The document title, for display.
    public let resourceTitle: String?

    public init(
        role: String,
        needsAuth: Bool? = nil,
        canClaim: Bool? = nil,
        wrongAccount: Bool? = nil,
        accepted: Bool? = nil,
        resourceTitle: String? = nil
    ) {
        self.role = role
        self.needsAuth = needsAuth
        self.canClaim = canClaim
        self.wrongAccount = wrongAccount
        self.accepted = accepted
        self.resourceTitle = resourceTitle
    }
}

// MARK: - Request bodies (G24)

/// `POST /api/documents/folders/{id}/documents` body.
///
/// Deliberately **has no `folderId`** — the folder is the path. This is the
/// only way to create a document inside a folder: `POST /api/documents`
/// documents itself as "always creates at root: there is no `folderId` in its
/// body", so a `folderId` passed there is silently dropped.
public struct CreateDocumentInFolderRequest: Codable, Sendable, Equatable {
    public let title: String
    public let content: String
    public let relativePath: String?
    public let isPublic: Bool?

    public init(
        title: String,
        content: String,
        relativePath: String? = nil,
        isPublic: Bool? = nil
    ) {
        self.title = title
        self.content = content
        self.relativePath = relativePath
        self.isPublic = isPublic
    }
}

/// `PATCH /api/documents/{id}` body for a **move**, and only a move.
///
/// It exists because `UpdateDocumentRequest` cannot express "move to root".
/// Codable's synthesised encoding uses `encodeIfPresent` for optionals, so a
/// `nil` `folderId` is *omitted*, and an omitted key is "leave it alone" —
/// the document would never leave its folder. This type always writes the
/// key, emitting an explicit `null` for root.
public struct MoveDocumentRequest: Encodable, Sendable, Equatable {
    /// Destination folder, or `nil` for "no folder (root)".
    public let folderId: String?

    public init(folderId: String?) {
        self.folderId = folderId
    }

    private enum CodingKeys: String, CodingKey {
        case folderId
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // `encode`, never `encodeIfPresent`: the explicit `null` is the wire
        // signal for "move out of every folder".
        try c.encode(folderId, forKey: .folderId)
    }
}
