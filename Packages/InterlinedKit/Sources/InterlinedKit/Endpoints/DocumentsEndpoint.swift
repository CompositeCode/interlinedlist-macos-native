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
    public static func create(_ body: CreateDocumentRequest) -> Request<DocumentDTO> {
        Request(method: .post, path: "/api/documents", body: .json(body), auth: .bearer)
    }

    /// `GET /api/documents/[id]`
    public static func get(id: String) -> Request<DocumentDTO> {
        Request(method: .get, path: "/api/documents/\(id)", auth: .bearer)
    }

    /// `PATCH /api/documents/[id]`
    public static func update(id: String, _ body: UpdateDocumentRequest) -> Request<DocumentDTO> {
        Request(method: .patch, path: "/api/documents/\(id)", body: .json(body), auth: .bearer)
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
    public static func createFolder(_ body: CreateDocumentFolderRequest) -> Request<DocumentFolderDTO> {
        Request(method: .post, path: "/api/documents/folders", body: .json(body), auth: .bearer)
    }

    /// `GET /api/documents/folders/[id]`
    public static func folder(id: String) -> Request<DocumentFolderDTO> {
        Request(method: .get, path: "/api/documents/folders/\(id)", auth: .bearer)
    }

    /// `PATCH /api/documents/folders/[id]`
    public static func updateFolder(
        id: String,
        _ body: UpdateDocumentFolderRequest
    ) -> Request<DocumentFolderDTO> {
        Request(method: .patch, path: "/api/documents/folders/\(id)", body: .json(body), auth: .bearer)
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
