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
            paginationKey: "lists"
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
            paginationKey: "rows"
        )
    }

    /// `POST /api/lists/[id]/data` — append a row.
    ///
    /// VERIFIED live 2026-09-06: answers the `{ message, data }` envelope, not a
    /// bare `ListRowDTO`. See `CreateListRowRequest` for the matching `data`
    /// request-field correction — both were wrong, so row creation failed twice
    /// over (work-consolidation.md §1c · V3).
    public static func createRow(listId: String, _ body: CreateListRowRequest) -> Request<ListRowWriteResponse> {
        Request(method: .post, path: "/api/lists/\(listId)/data", body: .json(body), auth: .bearer)
    }

    /// `GET /api/lists/[id]/data/[rowId]` — one row.
    ///
    /// VERIFIED live 2026-09-06: answers `{ "data": { …row… } }` (no `message`
    /// on the read), sharing the `ListRowWriteResponse` envelope. Was decoding a
    /// bare `ListRowDTO`, so the row inspector never loaded a row.
    public static func row(listId: String, rowId: String) -> Request<ListRowWriteResponse> {
        Request(method: .get, path: "/api/lists/\(listId)/data/\(rowId)", auth: .bearer)
    }

    /// `PUT /api/lists/[id]/data/[rowId]` — replace a row's cell values.
    ///
    /// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V3). This call was
    /// wrong in **three** ways at once, all fixed here and each confirmed
    /// against the test account:
    ///   1. **Verb** — `OPTIONS` reports `Allow: DELETE, GET, HEAD, OPTIONS, PUT`
    ///      and the shipped `PATCH` returns **405**.
    ///   2. **Request field** — the body is `{ "data": … }`; the shipped
    ///      `{ "rowData": … }` returns `400 "Data is required"` even on `PUT`.
    ///   3. **Response shape** — the reply is `{ message, data }`, not a bare
    ///      `ListRowDTO`.
    /// A live `PUT` carrying the corrected body returned HTTP 200 and the
    /// updated row.
    public static func updateRow(
        listId: String,
        rowId: String,
        _ body: UpdateListRowRequest
    ) -> Request<ListRowWriteResponse> {
        Request(method: .put, path: "/api/lists/\(listId)/data/\(rowId)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/lists/[id]/data/[rowId]`
    public static func deleteRow(listId: String, rowId: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/lists/\(listId)/data/\(rowId)", auth: .bearer)
    }

    // MARK: - Shared with me (work-consolidation.md G23 / issue #48)

    /// `GET /api/lists/watching` — lists **other people** shared with the
    /// caller. The web renders this as the datagrid on `/lists`; the macOS
    /// sidebar had no equivalent before G23.
    ///
    /// VERIFIED live 2026-09-09 (`200`, three rows, `allow: GET, HEAD,
    /// OPTIONS`): `{ "lists": [ …list superset… ], "pagination": {…} }`. Each
    /// row carries `role` (the *caller's* role), an embedded `user` (the
    /// owner), and a `parent` projection — see `ListDTO`.
    public static func watching(
        limit: Int? = nil,
        offset: Int? = nil,
        page: Int? = nil
    ) -> Request<Paginated<ListDTO>> {
        Request(
            method: .get,
            path: "/api/lists/watching",
            query: [
                .int("limit", limit),
                .int("offset", offset),
                .int("page", page)
            ],
            auth: .bearer,
            paginationKey: "lists"
        )
    }

    /// `GET /api/lists/[id]/contributors` — the full ranked contributor list.
    ///
    /// VERIFIED live 2026-09-09 (`200`, `allow: GET, HEAD, OPTIONS`). Unpaged
    /// by design ("no server paging" — live OpenAPI summary).
    public static func contributors(listId: String) -> Request<ListContributorsResponse> {
        Request(method: .get, path: "/api/lists/\(listId)/contributors", auth: .bearer)
    }

    // MARK: - Token-scoped share reads (no auth)
    //
    // The share-*link* builders live in `SharingEndpoint` (`Sharing.…`); these
    // two sit here because they are list-shaped reads that the Lists UI
    // consumes directly, and because issue #48 scopes them to this file. The
    // matching write halves (`POST /api/lists/shared/{token}` and
    // `POST /api/lists/invite/{token}`) are declared `x-auth-type: session` in
    // the live spec and are therefore deliberately absent: a Bearer-only
    // client cannot reach them, so there is no builder to call.

    /// `GET /api/lists/shared/{token}/data` — read-only row data for a
    /// token-shared list. Public: the **token is the capability**, so rows are
    /// served regardless of `isPublic` and with no session at all.
    ///
    /// VERIFIED live 2026-09-09: `allow: GET, HEAD, OPTIONS`, and an unknown
    /// token answers `404 {"error":"Share link not found, expired, or
    /// revoked","code":"not_found"}`. `/help/api/sharing` states it "returns
    /// the same row payload shape" as `GET /api/lists/:id/data`, i.e. the
    /// `{ rows, pagination }` envelope.
    public static func sharedRows(
        token: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<ListRowDTO>> {
        Request(
            method: .get,
            path: "/api/lists/shared/\(token)/data",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .none,
            paginationKey: "rows"
        )
    }

    /// `GET /api/lists/invite/{token}` — the email-invite landing payload.
    ///
    /// VERIFIED live 2026-09-09: reachable with no auth; an unknown token
    /// answers `404 {"error":"Invite not found, expired, or revoked"}`.
    /// Authentication is *optional* — signing in only changes `canClaim` /
    /// `wrongAccount`; the invited address is never returned.
    public static func invite(token: String) -> Request<ResolvedListInviteDTO> {
        Request(method: .get, path: "/api/lists/invite/\(token)", auth: .none)
    }

    // MARK: - Watchers / sharing

    /// `GET /api/lists/[id]/watchers` — owner-only.
    ///
    /// VERIFIED live 2026-09-09: answers `{ watchers: [...], pagination }`, not
    /// a bare array. See `ListWatchersResponse`.
    public static func watchers(listId: String) -> Request<ListWatchersResponse> {
        Request(method: .get, path: "/api/lists/\(listId)/watchers", auth: .bearer)
    }

    /// `GET /api/lists/[id]/watchers/me`
    public static func myWatcherStatus(listId: String) -> Request<ListWatcherStatusDTO> {
        Request(method: .get, path: "/api/lists/\(listId)/watchers/me", auth: .bearer)
    }

    /// `GET /api/lists/[id]/watchers/users` — search **candidates** to add.
    ///
    /// Owner-only. `excludeWatchers` takes comma-separated ids; when it is
    /// omitted the server auto-excludes the list's current watchers, which is
    /// what the add-watcher picker wants, so the builder leaves it off.
    ///
    /// VERIFIED live 2026-09-09: answers `{ users, total, pagination }` —
    /// people rows, not watcher rows. See `ListWatcherCandidatesResponse`.
    public static func watcherCandidates(
        listId: String,
        search: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<ListWatcherCandidatesResponse> {
        Request(
            method: .get,
            path: "/api/lists/\(listId)/watchers/users",
            query: [
                .string("search", search),
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer
        )
    }

    /// `POST /api/lists/[id]/watchers` — add a watcher (work-consolidation.md
    /// G23). Owner-granting a named user is **subscriber-gated** server-side
    /// (`403 {"error":"Subscribe to share lists."}` for a free owner); the
    /// self-subscribe branch (no `userId`) is free.
    ///
    /// VERIFIED live 2026-09-09 by `OPTIONS`: `allow: GET, HEAD, OPTIONS, POST`.
    /// The body/response shapes come from `/help/api/lists` — the write itself
    /// was not exercised (the recon account is shared; G23 recon was read-only).
    public static func addWatcher(
        listId: String,
        _ body: AddListWatcherRequest
    ) -> Request<AddListWatcherResponse> {
        Request(method: .post, path: "/api/lists/\(listId)/watchers", body: .json(body), auth: .bearer)
    }

    /// `PUT /api/lists/[id]/watchers/[userId]` — change a role. Owner-only and
    /// subscriber-gated. Answers `{ role }`, not the watcher row.
    public static func setWatcher(
        listId: String,
        userId: String,
        _ body: UpdateListWatcherRequest
    ) -> Request<SetListWatcherRoleResponse> {
        Request(method: .put, path: "/api/lists/\(listId)/watchers/\(userId)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/lists/[id]/watchers/[userId]` — not subscriber-gated, so a
    /// downgraded owner can always revoke access.
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
            paginationKey: "lists"
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
            paginationKey: "rows"
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
