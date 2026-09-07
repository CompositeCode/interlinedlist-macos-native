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
