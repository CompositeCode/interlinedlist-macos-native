import Foundation

/// Request builders for the **Documents & Sync** API group — the delta sync
/// interface, document CRUD, document image upload, and folder CRUD.
///
/// Follows the `Request.swift` conventions: one `public enum` namespace,
/// factories returning `Request<DTO>`, `Paginated<T>` + `paginationKey`
/// (collection key `"data"`) for list envelopes, explicit `AuthRequirement`,
/// path-only URLs, nil-skipping query items, `RequestBody.json` /
/// `RequestBody.raw` for uploads, and never throwing.
///
/// Auth: all `.bearer` (decision 0001 — Bearer works across the documents
/// surface; only `/api/user/identities`, `/api/user/organizations`, and
/// `/api/exports/*` are session-only).
public enum Documents {

    // MARK: - Sync

    /// `GET /api/documents/sync` — delta sync. Pass `lastSyncAt` for an
    /// incremental pull; omit for a full snapshot.
    public static func sync(lastSyncAt: String? = nil) -> Request<DocumentSyncResponse> {
        Request(
            method: .get,
            path: "/api/documents/sync",
            query: [.string("lastSyncAt", lastSyncAt)],
            auth: .bearer
        )
    }

    /// `POST /api/documents/sync` — push a batch of local create/update/delete
    /// operations.
    public static func pushSync(_ body: DocumentSyncRequest) -> Request<DocumentSyncResultDTO> {
        Request(method: .post, path: "/api/documents/sync", body: .json(body), auth: .bearer)
    }

    // MARK: - Document CRUD

    /// `GET /api/documents`
    public static func list(
        folderId: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<DocumentDTO>> {
        Request(
            method: .get,
            path: "/api/documents",
            query: [
                .string("folderId", folderId),
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer,
            paginationKey: "documents"
        )
    }

    /// `POST /api/documents`
    ///
    /// VERIFIED live 2026-09-06: answers `{ message, document }`, not a bare DTO.
    public static func create(_ body: CreateDocumentRequest) -> Request<DocumentResponse> {
        Request(method: .post, path: "/api/documents", body: .json(body), auth: .bearer)
    }

    /// `GET /api/documents/[id]`
    ///
    /// VERIFIED live 2026-09-06: answers `{ "document": { … } }` (no `message`
    /// on the read), not a bare DTO.
    public static func get(id: String) -> Request<DocumentResponse> {
        Request(method: .get, path: "/api/documents/\(id)", auth: .bearer)
    }

    /// `PATCH /api/documents/[id]` — merge the supplied fields only.
    ///
    /// VERIFIED live 2026-09-06: answers `{ message, document }`, not a bare
    /// DTO. A title-only `PATCH` left `content` intact, confirming it is a true
    /// partial update.
    public static func update(id: String, _ body: UpdateDocumentRequest) -> Request<DocumentResponse> {
        Request(method: .patch, path: "/api/documents/\(id)", body: .json(body), auth: .bearer)
    }

    /// `PUT /api/documents/[id]` — full replace (work-consolidation.md G27).
    ///
    /// VERIFIED live 2026-09-06: `OPTIONS` reports
    /// `Allow: DELETE, GET, HEAD, OPTIONS, PATCH, PUT`, and a live `PUT`
    /// carrying `title` + `content` replaced both and returned the same
    /// `{ message, document }` envelope as `PATCH`. Use `update` for a partial
    /// edit; this is the whole-document variant.
    public static func replace(id: String, _ body: UpdateDocumentRequest) -> Request<DocumentResponse> {
        Request(method: .put, path: "/api/documents/\(id)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/documents/[id]`
    public static func delete(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/documents/\(id)", auth: .bearer)
    }

    /// `POST /api/documents/[id]/images/upload` — multipart image upload.
    /// The caller supplies the already-encoded multipart body and its
    /// `Content-Type` (with boundary); the kit forwards the bytes verbatim.
    public static func uploadImage(
        id: String,
        body: Data,
        contentType: String
    ) -> Request<DocumentImageUploadResponse> {
        Request(
            method: .post,
            path: "/api/documents/\(id)/images/upload",
            body: .raw(body, contentType: contentType),
            auth: .bearer
        )
    }

    // MARK: - Folders

    /// `GET /api/documents/folders`
    public static func folders(
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<DocumentFolderDTO>> {
        Request(
            method: .get,
            path: "/api/documents/folders",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer,
            paginationKey: "folders"
        )
    }

    /// `POST /api/documents/folders`
    /// VERIFIED live 2026-09-06: answers the `{ message, folder }` envelope,
    /// not a bare `DocumentFolderDTO`.
    public static func createFolder(_ body: CreateDocumentFolderRequest) -> Request<DocumentFolderResponse> {
        Request(method: .post, path: "/api/documents/folders", body: .json(body), auth: .bearer)
    }

    /// `GET /api/documents/folders/[id]`
    ///
    /// VERIFIED live 2026-09-06: answers `{ "folder": { … } }` (no `message` on
    /// the read). Was decoding a bare DTO, so folder detail never loaded.
    public static func folder(id: String) -> Request<DocumentFolderResponse> {
        Request(method: .get, path: "/api/documents/folders/\(id)", auth: .bearer)
    }

    /// `PUT /api/documents/folders/[id]` — rename or re-parent a folder.
    ///
    /// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V5): the verb is
    /// `PUT`. `OPTIONS` reports `Allow: DELETE, GET, HEAD, OPTIONS, PUT` and the
    /// `PATCH` this shipped with returns **405**. A live `PUT` renamed a probe
    /// folder and returned HTTP 200 with the `{ message, folder }` envelope, so
    /// the response type is corrected alongside the verb.
    public static func updateFolder(
        id: String,
        _ body: UpdateDocumentFolderRequest
    ) -> Request<DocumentFolderResponse> {
        Request(method: .put, path: "/api/documents/folders/\(id)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/documents/folders/[id]`
    public static func deleteFolder(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/documents/folders/\(id)", auth: .bearer)
    }

    // MARK: - Sidebar tree (work-consolidation.md G24)

    /// `GET /api/documents/tree` — the entire sidebar in a single call:
    /// every folder (flat, nested via `parentId`) with its documents inline,
    /// plus the unfiled documents as a sibling `rootDocuments` array.
    ///
    /// VERIFIED live 2026-09-09 (read-only Bearer probe, `.env` test account):
    /// HTTP 200, and `OPTIONS` reports `Allow: GET, HEAD, OPTIONS`. The live
    /// OpenAPI spec marks it `x-auth-type: sync-token`, `x-subscription-tier:
    /// free`. See `DocumentTreeResponse` for the body and its two consumer
    /// constraints (root documents are a sibling array; `_templates` comes
    /// back inline).
    ///
    /// This replaces the sidebar's `folders(limit:offset:)` fetch. It does
    /// **not** replace `folderDocuments(id:)` / `list()`: the tree's inline
    /// document rows carry no `content` and no `updatedAt`, so a list column
    /// that orders by recency or an editor that opens a body still needs the
    /// heavier per-folder read.
    public static func tree() -> Request<DocumentTreeResponse> {
        Request(method: .get, path: "/api/documents/tree", auth: .bearer)
    }

    // MARK: - Public documents by user (work-consolidation.md G24)

    /// `GET /api/users/[username]/documents` — a user's public documents.
    ///
    /// VERIFIED live 2026-09-09: `auth: .none` is deliberate and checked —
    /// the spec reports `x-auth-type: none` and the route returned the same
    /// body with and without an `Authorization` header. Sending Bearer here
    /// would work but would misreport the endpoint's contract.
    public static func publicDocuments(username: String) -> Request<PublicUserDocumentsResponse> {
        Request(
            method: .get,
            path: "/api/users/\(username)/documents",
            auth: .none
        )
    }

    // MARK: - Create inside a folder (work-consolidation.md G24)

    /// `POST /api/documents/folders/[id]/documents` — create a document
    /// **directly in a folder**.
    ///
    /// VERIFIED live 2026-09-09 via `OPTIONS`, which reports
    /// `Allow: GET, HEAD, OPTIONS, POST` (no write was performed — the test
    /// account is shared). The spec marks it `x-subscription-tier: subscriber`
    /// and answers `201`.
    ///
    /// This is the *only* route that files a new document into a folder. The
    /// live reference is explicit that `POST /api/documents` "always creates
    /// at root: there is no `folderId` in its body", so passing a folder there
    /// is silently ignored. `DocumentsService.createDocument(inFolder:…)`
    /// routes here whenever a folder is selected.
    public static func createInFolder(
        folderId: String,
        _ body: CreateDocumentInFolderRequest
    ) -> Request<DocumentResponse> {
        Request(
            method: .post,
            path: "/api/documents/folders/\(folderId)/documents",
            body: .json(body),
            auth: .bearer
        )
    }

    // MARK: - Move between folders (work-consolidation.md G24)

    /// `PATCH /api/documents/[id]` carrying only `folderId` — move a document
    /// into a folder, or out to root when `folderId` is `nil`.
    ///
    /// Split out from `update(id:_:)` because only `MoveDocumentRequest` can
    /// encode the explicit `null` that means "no folder (root)"; the general
    /// `UpdateDocumentRequest` omits nil keys, which the server reads as
    /// "leave the folder alone". The live reference states `PUT` and `PATCH`
    /// "accept `folderId` to move a document into (or out of) a folder".
    public static func move(id: String, toFolderId folderId: String?) -> Request<DocumentResponse> {
        Request(
            method: .patch,
            path: "/api/documents/\(id)",
            body: .json(MoveDocumentRequest(folderId: folderId)),
            auth: .bearer
        )
    }

    // MARK: - Invite landing (work-consolidation.md G24)

    /// `GET /api/documents/invite/[token]` — resolve an email invite for its
    /// landing page. Public: `auth: .none`.
    ///
    /// VERIFIED live 2026-09-09 unauthenticated: an unknown token answers
    /// `404 {"error":"Invite not found, expired, or revoked","code":
    /// "not_found"}`, and `OPTIONS` reports `Allow: GET, HEAD, OPTIONS, POST`.
    ///
    /// **There is deliberately no accept builder.** `POST /api/documents/
    /// invite/[token]` is `x-auth-type: session` in the live spec — it is
    /// authenticated by the browser session cookie only, so a Bearer sync-token
    /// client cannot claim an invite no matter how the request is shaped. The
    /// Mac renders the landing state and hands the accept step to the browser.
    public static func invite(token: String) -> Request<DocumentInviteLandingDTO> {
        Request(
            method: .get,
            path: "/api/documents/invite/\(token)",
            auth: .none
        )
    }

    /// `GET /api/documents/folders/[id]/documents`
    public static func folderDocuments(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<DocumentDTO>> {
        Request(
            method: .get,
            path: "/api/documents/folders/\(id)/documents",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer,
            paginationKey: "documents"
        )
    }
}
