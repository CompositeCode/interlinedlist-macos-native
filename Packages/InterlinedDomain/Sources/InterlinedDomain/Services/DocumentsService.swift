import Foundation
import InterlinedKit

// MARK: - DocumentsError

/// Domain-level errors surfaced by `DocumentsService`. Transport / status /
/// decode failures continue to surface as `APIError` — these are the
/// domain-layer error cases the kit cannot express.
public enum DocumentsError: Error, Sendable, Equatable {

    /// The requested document id was not found.
    case notFound

    /// A locally-edited document is out of date with the server. Carries the
    /// local id under conflict and the server's reported version (or
    /// `updatedAt` ISO string when no version field is present).
    case conflict(localId: String, serverVersion: String)

    /// The supplied image exceeded the byte budget after every prep pass.
    /// Wraps `ImagePrepError.tooLargeAfterAllAttempts` so view code switches
    /// on `DocumentsError`, not the imaging error.
    case imageTooLargeAfterPrep

    /// The sync engine refused to complete a cycle. Carries the underlying
    /// transport / API failure unchanged so the UI can still inspect it.
    /// Wrapped as `APIError` when the underlying source was one, or
    /// `.transport(message:)` when it wasn't (kept here so the persistence
    /// package can construct one without depending on `InterlinedKit`).
    case syncFailed(underlying: APIError)
}

extension DocumentsError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound:
            return "Document not found."
        case .conflict(let localId, let serverVersion):
            return "Document \(localId) is out of date (server version: \(serverVersion))."
        case .imageTooLargeAfterPrep:
            return "Image is too large to upload, even after compression."
        case .syncFailed(let underlying):
            return "Document sync failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - DocumentSyncCoordinating

/// Sync seam the `DocumentsService` delegates to. The concrete
/// `DocumentSyncEngine` lives in `InterlinedPersistence` (it needs the
/// SwiftData store), but the surface lives here so view code only sees a
/// domain protocol and the App layer doesn't import the kit.
public protocol DocumentSyncCoordinating: Sendable {
    /// Pull the delta, resolve conflicts, push the outbox, return the report.
    func syncNow() async throws -> DocumentSyncReport

    /// Append a local change to the outbox. The next `syncNow()` cycle will
    /// flush it. Non-throwing — the persistence layer logs and the change
    /// stays queued until the next attempt succeeds.
    func enqueue(_ change: DocumentChange) async

    /// The shared event stream. The App layer subscribes; rebinds list
    /// views on `deltaApplied`, shows banners on `conflictResolved`, drops
    /// optimistic chrome on `pushed`.
    var events: AsyncStream<DocumentSyncEvent> { get }
}

// MARK: - DocumentsServicing

/// The documents surface the App layer codes against (PLAN.md §6 M4). Wraps
/// the kit's `Documents` builders and the `DocumentSyncCoordinating` seam so
/// view code never sees DTOs or the sync engine directly.
public protocol DocumentsServicing: Sendable {

    // MARK: - Documents

    /// Lists documents in `folder` (or root when `nil`). Routes through
    /// `/api/documents/folders/[id]/documents` for non-nil folders so the
    /// server-side filter is authoritative.
    ///
    /// When a `DocumentStore` is injected the fetched documents are written
    /// through (upserted) to the cache so a later `cachedDocuments(in:)` read
    /// serves them; the network read is authoritative and does not fall back
    /// to cache on failure (the sync engine owns offline reconciliation).
    func documents(in folder: FolderNode.ID?, limit: Int, offset: Int) async throws -> [Document]

    /// The cached documents in `folderID` (or root when `nil`), so a view can
    /// paint before the network / sync returns. Filters `store.allDocuments()`
    /// by `folderId`; empty when no store is injected or the cache is cold.
    func cachedDocuments(in folderID: FolderNode.ID?) async -> [Document]

    /// The cached folders, so the source list can paint before the network /
    /// sync returns. Empty when no store is injected or the cache is cold.
    func cachedFolders() async -> [FolderNode]

    /// Loads one document by id.
    func document(id: String) async throws -> Document

    /// Creates a new document.
    func create(title: String, body: String, folderId: String?, isPublic: Bool) async throws -> Document

    /// Updates a document's title and body.
    func update(id: String, title: String?, body: String?, folderId: String?, isPublic: Bool?) async throws -> Document

    /// Deletes a document.
    func delete(id: String) async throws

    /// Uploads an image attachment for a document. Calls `ImagePrep.prepare`
    /// before forwarding to `Documents.uploadImage`; bubbles
    /// `DocumentsError.imageTooLargeAfterPrep` when no prep pass fits the
    /// byte budget.
    func uploadImage(in documentId: String, image: Data, suggestedName: String?) async throws -> URL

    // MARK: - Folders

    func folders(limit: Int, offset: Int) async throws -> [FolderNode]
    func folder(id: String) async throws -> FolderNode
    func createFolder(name: String, parentId: String?) async throws -> FolderNode
    func renameFolder(id: String, to name: String) async throws -> FolderNode
    func deleteFolder(id: String) async throws

    // MARK: - Sync passthrough

    /// Runs one full sync cycle through the injected coordinator.
    func syncNow() async throws -> DocumentSyncReport

    /// Appends an offline change to the outbox.
    func enqueueOfflineWrite(_ change: DocumentChange) async

    /// The shared sync event stream. `nil` when no coordinator was injected
    /// (caller is using the service without offline sync).
    var syncEvents: AsyncStream<DocumentSyncEvent>? { get }
}

// MARK: - DocumentsService

public final class DocumentsService: DocumentsServicing {

    private let api: APIClientProtocol
    private let sync: DocumentSyncCoordinating?
    private let store: DocumentStore?
    private let decoder: JSONDecoder

    /// Optional source of server-authoritative content limits (work-consolidation.md
    /// G14 tail). When present, `uploadImage` enforces the live `GET /api/limits`
    /// image ceilings; when `nil` the built-in `ImagePrep` constants apply.
    private let contentLimits: ContentLimitsProviding?

    /// - Parameters:
    ///   - api: networking seam (a stub in tests).
    ///   - sync: optional coordinator. When `nil`, sync methods throw and
    ///     `syncEvents` returns `nil` — the service still serves single-shot
    ///     CRUD just fine.
    ///   - store: optional cache port for the cache-first read surface. When
    ///     `nil`, `cachedDocuments`/`cachedFolders` return `[]` and the network
    ///     reads do not write through (the default keeps existing
    ///     `DocumentsService(api:sync:)` call sites source-compatible). Note
    ///     the sync engine owns the *same* store in production, so writes made
    ///     here and by the engine stay consistent.
    ///   - decoder: shared kit JSON configuration.
    ///   - contentLimits: optional live limits source for `uploadImage`
    ///     (defaults to `nil` → built-in `ImagePrep` constants).
    public init(
        api: APIClientProtocol,
        sync: DocumentSyncCoordinating? = nil,
        store: DocumentStore? = nil,
        decoder: JSONDecoder = JSONCoders.makeDecoder(),
        contentLimits: ContentLimitsProviding? = nil
    ) {
        self.api = api
        self.sync = sync
        self.store = store
        self.decoder = decoder
        self.contentLimits = contentLimits
    }

    // MARK: - Documents

    public func documents(
        in folder: FolderNode.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Document] {
        let request: Request<Paginated<DocumentDTO>>
        if let folder {
            request = Documents.folderDocuments(id: folder, limit: limit, offset: offset)
        } else {
            request = Documents.list(folderId: nil, limit: limit, offset: offset)
        }
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "documents"
        let items = try PaginatedDecoder.decodeItems(
            DocumentDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        let documents = items.map(Document.init(from:))
        // Write through so a later `cachedDocuments(in:)` serves these. These
        // are server-authoritative rows, so no local-edit flag (`nil`) — the
        // same "folding in a server delta" path the sync engine uses.
        if let store {
            for document in documents {
                await store.upsert(document, localEditedAt: nil)
            }
        }
        return documents
    }

    public func cachedDocuments(in folderID: FolderNode.ID?) async -> [Document] {
        guard let store else { return [] }
        let all = await store.allDocuments()
        // Filter to the requested folder (root == nil). Drop tombstoned rows so
        // a view never paints a document deleted upstream from the cache.
        return all.filter { $0.folderId == folderID && !$0.deleted }
    }

    public func cachedFolders() async -> [FolderNode] {
        guard let store else { return [] }
        return await store.allFolders().filter { !$0.deleted }
    }

    public func document(id: String) async throws -> Document {
        do {
            let dto = try await api.send(Documents.get(id: id))
            return Document(from: dto)
        } catch let error as APIError {
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    public func create(
        title: String,
        body: String,
        folderId: String?,
        isPublic: Bool
    ) async throws -> Document {
        let req = CreateDocumentRequest(
            title: title,
            content: body,
            folderId: folderId,
            relativePath: nil,
            isPublic: isPublic
        )
        let dto = try await api.send(Documents.create(req))
        return Document(from: dto)
    }

    public func update(
        id: String,
        title: String?,
        body: String?,
        folderId: String?,
        isPublic: Bool?
    ) async throws -> Document {
        let req = UpdateDocumentRequest(
            title: title,
            content: body,
            folderId: folderId,
            isPublic: isPublic
        )
        do {
            let dto = try await api.send(Documents.update(id: id, req))
            return Document(from: dto)
        } catch let error as APIError {
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    public func delete(id: String) async throws {
        do {
            try await api.sendVoid(Documents.delete(id: id))
        } catch let error as APIError {
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    public func uploadImage(
        in documentId: String,
        image: Data,
        suggestedName: String?
    ) async throws -> URL {
        // Prefer the live `GET /api/limits` image ceilings (work-consolidation.md
        // G14 tail); `ContentLimits.default` (== the built-in `ImagePrep`
        // constants) when no provider is injected or the fetch fails.
        let limits = await contentLimits?.limits() ?? .default
        let prepared: PreparedImage
        do {
            prepared = try ImagePrep.prepare(image, limits: limits.imagePrepLimits)
        } catch ImagePrepError.tooLargeAfterAllAttempts {
            throw DocumentsError.imageTooLargeAfterPrep
        }

        // Build a minimal multipart body. The boundary is a random UUID; the
        // server reads it from the Content-Type header. The single part is
        // named `file` with the suggested file name (falling back to a
        // generic one) and the matching MIME type.
        let boundary = "----InterlinedListBoundary-\(UUID().uuidString)"
        let filename = suggestedName ?? defaultFilename(for: prepared.format)
        let multipart = makeMultipartBody(
            boundary: boundary,
            fieldName: "file",
            filename: filename,
            mimeType: prepared.format.mimeType,
            data: prepared.data
        )
        let response = try await api.send(
            Documents.uploadImage(
                id: documentId,
                body: multipart,
                contentType: "multipart/form-data; boundary=\(boundary)"
            )
        )
        guard let url = URL(string: response.url) else {
            throw APIError.decoding(
                type: "DocumentImageUploadResponse.url",
                message: "Server returned a non-URL upload location: \(response.url)"
            )
        }
        return url
    }

    // MARK: - Folders

    public func folders(limit: Int, offset: Int) async throws -> [FolderNode] {
        let request = Documents.folders(limit: limit, offset: offset)
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "folders"
        let items = try PaginatedDecoder.decodeItems(
            DocumentFolderDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        let folders = items.map(FolderNode.init(from:))
        // Write through so a later `cachedFolders()` serves these.
        if let store {
            for folder in folders {
                await store.upsertFolder(folder)
            }
        }
        return folders
    }

    public func folder(id: String) async throws -> FolderNode {
        do {
            let dto = try await api.send(Documents.folder(id: id))
            return FolderNode(from: dto)
        } catch let error as APIError {
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    public func createFolder(name: String, parentId: String?) async throws -> FolderNode {
        let req = CreateDocumentFolderRequest(name: name, parentId: parentId)
        let dto = try await api.send(Documents.createFolder(req))
        return FolderNode(from: dto)
    }

    public func renameFolder(id: String, to name: String) async throws -> FolderNode {
        let req = UpdateDocumentFolderRequest(name: name, parentId: nil)
        do {
            let dto = try await api.send(Documents.updateFolder(id: id, req))
            return FolderNode(from: dto)
        } catch let error as APIError {
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    public func deleteFolder(id: String) async throws {
        do {
            try await api.sendVoid(Documents.deleteFolder(id: id))
        } catch let error as APIError {
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    // MARK: - Sync passthrough

    public func syncNow() async throws -> DocumentSyncReport {
        guard let sync else {
            // A service with no coordinator can't pretend to sync. Surface
            // the missing-dep as a transport error so the UI shows a clear
            // "offline sync unavailable" message instead of crashing.
            throw DocumentsError.syncFailed(
                underlying: .transport(message: "No DocumentSyncCoordinator is configured.")
            )
        }
        return try await sync.syncNow()
    }

    public func enqueueOfflineWrite(_ change: DocumentChange) async {
        await sync?.enqueue(change)
    }

    public var syncEvents: AsyncStream<DocumentSyncEvent>? {
        sync?.events
    }

    // MARK: - Multipart helpers

    private func makeMultipartBody(
        boundary: String,
        fieldName: String,
        filename: String,
        mimeType: String,
        data: Data
    ) -> Data {
        var body = Data()
        let header =
            "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n" +
            "Content-Type: \(mimeType)\r\n\r\n"
        body.append(Data(header.utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private func defaultFilename(for format: ImageFormat) -> String {
        switch format {
        case .png:  return "image.png"
        case .jpeg: return "image.jpg"
        case .heic: return "image.heic"
        }
    }
}
