import Foundation

/// Request builders for the **Lists** API group — list CRUD, schema, refresh,
/// dynamic-schema row data, watchers/sharing, the public (no-auth) browse
/// routes, and list connections.
///
/// Follows the conventions documented in `Request.swift`: one `public enum`
/// namespace, factories returning `Request<DTO>`, `Paginated<T>` +
/// `paginationKey` for list envelopes (collection key `"data"` per the API
/// reference), explicit `AuthRequirement`, path-only URLs, nil-skipping query
/// items, `RequestBody.json`, and never throwing.
///
/// Auth: list reads/writes are `.bearer` (decision 0001 — Bearer is the
/// near-universal transport; only `/api/user/identities`,
/// `/api/user/organizations`, and `/api/exports/*` use `.session`). The three
/// public browse routes (`/api/users/[username]/lists*`) are `.none`.
public enum Lists {

    // MARK: - List CRUD

    /// `GET /api/lists`
    public static func list(
        limit: Int? = nil,
        offset: Int? = nil,
        page: Int? = nil
    ) -> Request<Paginated<ListDTO>> {
        Request(
            method: .get,
            path: "/api/lists",
            query: [
                .int("limit", limit),
                .int("offset", offset),
                .int("page", page)
            ],
            auth: .bearer,
            paginationKey: "data"
        )
    }

    /// `POST /api/lists`
    public static func create(_ body: CreateListRequest) -> Request<ListDTO> {
        Request(method: .post, path: "/api/lists", body: .json(body), auth: .bearer)
    }

    /// `GET /api/lists/[id]`
    public static func get(id: String) -> Request<ListDTO> {
        Request(method: .get, path: "/api/lists/\(id)", auth: .bearer)
    }

    /// `PUT /api/lists/[id]`
    public static func update(id: String, _ body: UpdateListRequest) -> Request<ListDTO> {
        Request(method: .put, path: "/api/lists/\(id)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/lists/[id]`
    public static func delete(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/lists/\(id)", auth: .bearer)
    }

    // MARK: - Schema

    /// `GET /api/lists/[id]/schema`
    public static func schema(id: String) -> Request<ListSchemaDTO> {
        Request(method: .get, path: "/api/lists/\(id)/schema", auth: .bearer)
    }

    /// `PUT /api/lists/[id]/schema`
    public static func updateSchema(id: String, _ body: UpdateListSchemaRequest) -> Request<ListSchemaDTO> {
        Request(method: .put, path: "/api/lists/\(id)/schema", body: .json(body), auth: .bearer)
    }

    // MARK: - Refresh (GitHub-backed)

    /// `POST /api/lists/[id]/refresh`
    public static func refresh(id: String) -> Request<ListDTO> {
        Request(method: .post, path: "/api/lists/\(id)/refresh", auth: .bearer)
    }

    // MARK: - Row data (dynamic schema)

    /// `GET /api/lists/[id]/data`
    public static func rows(
        listId: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<ListRowDTO>> {
        Request(
            method: .get,
            path: "/api/lists/\(listId)/data",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer,
            paginationKey: "data"
        )
    }

    /// `POST /api/lists/[id]/data`
    public static func createRow(listId: String, _ body: CreateListRowRequest) -> Request<ListRowDTO> {
        Request(method: .post, path: "/api/lists/\(listId)/data", body: .json(body), auth: .bearer)
    }

    /// `GET /api/lists/[id]/data/[rowId]`
    public static func row(listId: String, rowId: String) -> Request<ListRowDTO> {
        Request(method: .get, path: "/api/lists/\(listId)/data/\(rowId)", auth: .bearer)
    }

    /// `PATCH /api/lists/[id]/data/[rowId]`
    public static func updateRow(
        listId: String,
        rowId: String,
        _ body: UpdateListRowRequest
    ) -> Request<ListRowDTO> {
        Request(method: .patch, path: "/api/lists/\(listId)/data/\(rowId)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/lists/[id]/data/[rowId]`
    public static func deleteRow(listId: String, rowId: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/lists/\(listId)/data/\(rowId)", auth: .bearer)
    }

    // MARK: - Watchers / sharing

    /// `GET /api/lists/[id]/watchers`
    public static func watchers(listId: String) -> Request<[ListWatcherDTO]> {
        Request(method: .get, path: "/api/lists/\(listId)/watchers", auth: .bearer)
    }

    /// `GET /api/lists/[id]/watchers/me`
    public static func myWatcherStatus(listId: String) -> Request<ListWatcherStatusDTO> {
        Request(method: .get, path: "/api/lists/\(listId)/watchers/me", auth: .bearer)
    }

    /// `GET /api/lists/[id]/watchers/users`
    public static func watcherUsers(listId: String) -> Request<[ListWatcherDTO]> {
        Request(method: .get, path: "/api/lists/\(listId)/watchers/users", auth: .bearer)
    }

    /// `PUT /api/lists/[id]/watchers/[userId]`
    public static func setWatcher(
        listId: String,
        userId: String,
        _ body: UpdateListWatcherRequest
    ) -> Request<ListWatcherDTO> {
        Request(method: .put, path: "/api/lists/\(listId)/watchers/\(userId)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/lists/[id]/watchers/[userId]`
    public static func removeWatcher(listId: String, userId: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/lists/\(listId)/watchers/\(userId)", auth: .bearer)
    }

    // MARK: - Public browse (no auth)

    /// `GET /api/users/[username]/lists` — public, no auth.
    public static func publicLists(
        username: String,
        limit: Int? = nil,
        offset: Int? = nil,
        page: Int? = nil
    ) -> Request<Paginated<ListDTO>> {
        Request(
            method: .get,
            path: "/api/users/\(username)/lists",
            query: [
                .int("limit", limit),
                .int("offset", offset),
                .int("page", page)
            ],
            auth: .none,
            paginationKey: "data"
        )
    }

    /// `GET /api/users/[username]/lists/[id]` — public, no auth.
    public static func publicList(username: String, id: String) -> Request<ListDTO> {
        Request(method: .get, path: "/api/users/\(username)/lists/\(id)", auth: .none)
    }

    /// `GET /api/users/[username]/lists/[id]/data` — public, no auth.
    public static func publicListRows(
        username: String,
        id: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<ListRowDTO>> {
        Request(
            method: .get,
            path: "/api/users/\(username)/lists/\(id)/data",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .none,
            paginationKey: "data"
        )
    }

    // MARK: - Connections

    /// `GET /api/lists/connections`
    public static func connections() -> Request<ListConnectionsResponse> {
        Request(method: .get, path: "/api/lists/connections", auth: .bearer)
    }

    /// `POST /api/lists/connections`
    public static func createConnection(_ body: CreateListConnectionRequest) -> Request<ListConnectionDTO> {
        Request(method: .post, path: "/api/lists/connections", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/lists/connections/[id]`
    public static func deleteConnection(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/lists/connections/\(id)", auth: .bearer)
    }
}
