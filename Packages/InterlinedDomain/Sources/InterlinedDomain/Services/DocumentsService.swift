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

    /// A subscriber-only documents action was attempted by a free account.
    /// Raised **before** any HTTP call so the UI can gate the affordance
    /// rather than surfacing a bare 403. Carries nothing: the only gated
    /// documents action today is creating a document, and the message is the
    /// same whichever route it came in on.
    ///
    /// TODO(#40): issue #40 owns `EntitlementsService` and is building a
    /// `CapabilityGate` whose denials carry a reason and run
    /// status → email-verification → tier, hardest first. When it lands, this
    /// case should carry that denial instead of standing alone, and the gate
    /// below should ask it rather than reading `isSubscriber`. Deliberately not
    /// done here: adding a `Feature` case means editing the file #40 owns, so
    /// this consumes the existing seam and leaves the enum untouched.
    ///
    /// Note the gate matches #40's published matrix: **creation only**. Moving,
    /// editing and deleting documents stay free on every tier, so a lapsed
    /// subscriber keeps existing content fully usable.
    case subscriberRequired

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
        case .subscriberRequired:
            return "Creating documents requires a subscription."
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

    /// Creates a document **inside** `folderId` via
    /// `POST /api/documents/folders/{id}/documents`.
    ///
    /// A separate method rather than a flag on `create(...)` because it is a
    /// different route with a different contract: `POST /api/documents`
    /// documents itself as "always creates at root — there is no `folderId`
    /// in its body", so the `folderId` argument on `create(...)` has never
    /// reached the server. Anything filing a document into a folder must come
    /// through here.
    ///
    /// Subscriber-gated (`x-subscription-tier: subscriber` on the live spec).
    /// The gate runs locally first and throws
    /// `DocumentsError.subscriberRequired` before any HTTP call.
    func createDocument(
        inFolder folderId: String,
        title: String,
        body: String,
        isPublic: Bool,
        relativePath: String?
    ) async throws -> Document

    /// Moves a document into `folderId`, or out to root when `folderId` is
    /// `nil`. Returns the relocated document as the server sees it.
    ///
    /// Distinct from `update(id:…folderId:…)` because only this path can
    /// express "no folder": `UpdateDocumentRequest` omits nil keys, and an
    /// omitted `folderId` means "leave it where it is".
    func moveDocument(id: String, toFolder folderId: String?) async throws -> Document

    // MARK: - Sidebar tree

    /// The whole documents sidebar in one call (`GET /api/documents/tree`):
    /// every folder with its documents inline, plus the unfiled root
    /// documents.
    ///
    /// This is the sidebar's single source. It replaces `folders(limit:offset:)`
    /// there, and it write-throughs its folders to the injected `DocumentStore`
    /// so `cachedFolders()` keeps serving the same stale-while-revalidate paint
    /// it did before.
    ///
    /// It does **not** replace `documents(in:limit:offset:)`: the tree's inline
    /// rows carry no body and no `updatedAt`, so the document list column and
    /// the editor still need the heavier read. Only the *folder* fetch retires.
    func documentTree() async throws -> DocumentTreeSnapshot

    // MARK: - Public documents

    /// A user's public documents (`GET /api/users/{username}/documents`).
    /// Unauthenticated — usable for any handle, including while signed out.
    func publicDocuments(ofUser username: String) async throws -> PublicUserDocuments

    // MARK: - Invites

    /// Resolves a document email invite for its landing page
    /// (`GET /api/documents/invite/{token}`).
    ///
    /// Landing only. There is no accept method and cannot be one: the claim
    /// route is session-cookie-authenticated, so a Bearer client hands the
    /// final step to the browser via `DocumentInvite.acceptURL(base:)`.
    func invite(token: String) async throws -> DocumentInvite

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

    /// Live entitlements, evaluated at call time on every gated write.
    ///
    /// A closure, not a stored value, for the same reason `MessagesService`
    /// uses one: the signed-in account's `customerStatus` changes mid-session
    /// (sign-in resolves, a subscription lapses, a 403 forces a re-fetch), and
    /// a snapshot taken at launch would gate on a stale answer. The App layer
    /// passes a reader over its `LiveEntitlements` box.
    ///
    /// Defaults to `.free` — a signed-out or unresolved session is never
    /// wrongly entitled.
    ///
    /// TODO(#40): the gate reads `EntitlementsService.isSubscriber` directly
    /// because `Feature` has no documents case yet. Issue #40 owns
    /// `EntitlementsService`; when its `CapabilityGate` lands, add a
    /// `Feature.documentCreation` case (named for creation, not `.documents`,
    /// to keep it unmissable that only creation is gated) and switch
    /// `requireSubscriber()` below to ask the gate. One line, no call sites.
    private let entitlementsProvider: @Sendable () -> EntitlementsService

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
        contentLimits: ContentLimitsProviding? = nil,
        entitlementsProvider: @escaping @Sendable () -> EntitlementsService = {
            EntitlementsService(customerStatus: .free)
        }
    ) {
        self.api = api
        self.sync = sync
        self.store = store
        self.decoder = decoder
        self.contentLimits = contentLimits
        self.entitlementsProvider = entitlementsProvider
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
            // The live read answers `{ document }`; unwrap it.
            let dto = try await api.send(Documents.get(id: id)).document
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
        // The live create answers `{ message, document }`; unwrap it.
        let dto = try await api.send(Documents.create(req)).document
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
            // The live update answers `{ message, document }`; unwrap it.
            let dto = try await api.send(Documents.update(id: id, req)).document
            return Document(from: dto)
        } catch let error as APIError {
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    public func createDocument(
        inFolder folderId: String,
        title: String,
        body: String,
        isPublic: Bool,
        relativePath: String?
    ) async throws -> Document {
        // Gate before the round-trip: a free account gets a typed domain error
        // and a useful message instead of a bare 403 from the wire.
        try requireSubscriber()
        let req = CreateDocumentInFolderRequest(
            title: title,
            content: body,
            relativePath: relativePath,
            isPublic: isPublic
        )
        do {
            // Same `{ message, document }` envelope as `POST /api/documents`.
            let dto = try await api.send(Documents.createInFolder(folderId: folderId, req)).document
            let document = Document(from: dto)
            // Write through so the folder's cached documents include the new
            // row before the next revalidation — same contract as `documents`.
            if let store {
                await store.upsert(document, localEditedAt: nil)
            }
            return document
        } catch let error as APIError {
            // A folder that vanished between the sidebar painting it and the
            // create landing reads as "not found" to the user, not as a raw
            // status code.
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            // The server gates this route too. Translate its 403 into the same
            // typed error the local gate raises so callers branch once.
            if case .forbidden = error {
                throw DocumentsError.subscriberRequired
            }
            throw error
        }
    }

    public func moveDocument(id: String, toFolder folderId: String?) async throws -> Document {
        do {
            // `Documents.move` encodes an explicit `null` for root; a plain
            // `update(folderId: nil)` would omit the key and move nothing.
            let dto = try await api.send(Documents.move(id: id, toFolderId: folderId)).document
            let document = Document(from: dto)
            if let store {
                await store.upsert(document, localEditedAt: nil)
            }
            return document
        } catch let error as APIError {
            // Covers both halves of the invalid case: a document that was
            // deleted underneath us, and a destination folder that no longer
            // exists — the server answers 404 for either.
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    // MARK: - Sidebar tree

    public func documentTree() async throws -> DocumentTreeSnapshot {
        let response = try await api.send(Documents.tree())
        let snapshot = DocumentTreeSnapshot(from: response)
        // Write the folders through so `cachedFolders()` keeps painting the
        // sidebar before the network returns. Only folders: the tree's
        // document rows are summaries without a body or `updatedAt`, and
        // upserting those into the document cache would overwrite real cached
        // documents with emptier ones — the precise regression the summary
        // type exists to prevent.
        if let store {
            for folder in snapshot.folders {
                await store.upsertFolder(folder)
            }
        }
        return snapshot
    }

    // MARK: - Public documents

    public func publicDocuments(ofUser username: String) async throws -> PublicUserDocuments {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Invalid input: an empty handle would resolve to
            // `/api/users//documents`, a different route entirely. Refuse
            // before the request rather than asking the server about it.
            throw DocumentsError.notFound
        }
        do {
            let response = try await api.send(Documents.publicDocuments(username: trimmed))
            return PublicUserDocuments(username: trimmed, from: response)
        } catch let error as APIError {
            if case .notFound = error {
                throw DocumentsError.notFound
            }
            throw error
        }
    }

    // MARK: - Invites

    public func invite(token: String) async throws -> DocumentInvite {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DocumentsError.notFound
        }
        do {
            let dto = try await api.send(Documents.invite(token: trimmed))
            return DocumentInvite(token: trimmed, from: dto)
        } catch let error as APIError {
            // The server deliberately collapses unknown / expired / revoked /
            // deleted-document into one 404 so tokens can't be probed. Keep
            // that collapse — do not try to distinguish them in the UI.
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
            // The live read answers `{ folder }`; unwrap it.
            let dto = try await api.send(Documents.folder(id: id)).folder
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
        // The live create answers `{ message, folder }`; unwrap it.
        let dto = try await api.send(Documents.createFolder(req)).folder
        return FolderNode(from: dto)
    }

    public func renameFolder(id: String, to name: String) async throws -> FolderNode {
        let req = UpdateDocumentFolderRequest(name: name, parentId: nil)
        do {
            // The live update answers `{ message, folder }`; unwrap it.
            let dto = try await api.send(Documents.updateFolder(id: id, req)).folder
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

    // MARK: - Entitlement gate

    /// Throws `DocumentsError.subscriberRequired` when the live account is not
    /// a subscriber. The single place the documents surface consults
    /// entitlements, so the #40 follow-up is a one-line change here.
    private func requireSubscriber() throws {
        guard entitlementsProvider().isSubscriber else {
            throw DocumentsError.subscriberRequired
        }
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
