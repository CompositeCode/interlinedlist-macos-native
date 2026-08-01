import Foundation

/// Request builders for the **List Folders** API group (the-gaps.md G6) —
/// hierarchical folders that organize the current user's lists. Distinct from
/// document folders (`/api/documents/folders/*`); these live at `/api/folders`.
///
/// Paths verified live 2026-07-31 (`GET /api/folders` → 200 `{folders:[]}`).
/// Creating a folder is subscriber-gated server-side; the domain service also
/// checks entitlements before calling.
///
/// Follows the `Request.swift` conventions: factories returning `Request<DTO>`,
/// explicit `.bearer` auth, path-only URLs, `RequestBody.json` for bodies.
public enum ListFolders {

    /// `GET /api/folders` — all non-deleted list folders (flat array).
    public static func list() -> Request<ListFoldersResponse> {
        Request(method: .get, path: "/api/folders", auth: .bearer)
    }

    /// `POST /api/folders` — create a folder (subscriber only).
    public static func create(_ body: CreateListFolderRequest) -> Request<ListFolderDTO> {
        Request(method: .post, path: "/api/folders", body: .json(body), auth: .bearer)
    }

    /// `PUT /api/folders/{id}` — rename and/or move a folder.
    public static func update(id: String, _ body: UpdateListFolderRequest) -> Request<ListFolderDTO> {
        Request(method: .put, path: "/api/folders/\(id)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/folders/{id}` — soft-delete a folder (its lists detach to
    /// root; child folders cascade).
    public static func delete(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/folders/\(id)", auth: .bearer)
    }
}
