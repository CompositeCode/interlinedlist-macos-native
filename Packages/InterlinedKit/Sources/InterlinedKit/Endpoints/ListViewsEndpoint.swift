import Foundation

/// Request builders for **saved list views** — the five
/// `/api/lists/{id}/views*` routes (work-consolidation.md G40 / issue #81).
///
/// Lives beside `ListsEndpoint.swift` rather than inside it: the five routes
/// are one coherent sub-resource with their own DTO family, and `Lists` is
/// already a 360-line namespace covering CRUD, schema, rows, watchers, sharing
/// and connections. Same `public enum Lists` namespace, so call sites read
/// `Lists.views(listId:)` alongside `Lists.rows(listId:)`.
///
/// **Auth: `.bearer`, and no subscription gate.** All five are declared
/// `x-auth-type: sync-token` and `x-subscription-tier: free`, and all five
/// were reached live on 2026-09-15 with a Bearer token on a **free** account.
/// Do not add an entitlement check around them — a free user arranging their
/// own list is not a paid feature, and gating it would hide views the server
/// happily serves (the GitHub #40 rule: creation is gated, arrangement is not).
extension Lists {

    // MARK: - Saved views

    /// `GET /api/lists/[id]/views` → `{"views":[…]}`.
    ///
    /// Returns every **shared** view on the list plus the caller's **personal**
    /// views, in one flat array. Unpaged — the route returns no pagination
    /// envelope, so there is no `paginationKey` here.
    ///
    /// VERIFIED live: `200 {"views":[]}` on a list with no saved views
    /// (re-read 2026-09-16), and a populated array carrying the eight-key row
    /// documented on `ListViewDTO` (2026-09-15).
    public static func views(listId: String) -> Request<ListViewsResponse> {
        Request(method: .get, path: "/api/lists/\(listId)/views", auth: .bearer)
    }

    /// `POST /api/lists/[id]/views` → `201 {"view":{…}}`.
    ///
    /// `scope` is the one validated field: an unknown token answers
    /// `400 {"error":"scope must be \"personal\" or \"shared\"","code":"bad_request"}`.
    /// Every `config` value, by contrast, defaults silently — see
    /// `ListViewConfigDTO`.
    public static func createView(
        listId: String,
        _ body: CreateListViewRequest
    ) -> Request<ListViewResponse> {
        Request(method: .post, path: "/api/lists/\(listId)/views", body: .json(body), auth: .bearer)
    }

    /// `POST /api/lists/[id]/views/[viewId]` → `201 {"view":{…}}` — fork.
    ///
    /// The **same verb and a deeper path** than create, which is the only thing
    /// distinguishing the two: `POST …/views` creates, `POST …/views/{id}`
    /// copies. Getting that backwards would silently create a blank view
    /// instead of duplicating one, so the two builders are named for what they
    /// do rather than for their verb.
    public static func forkView(
        listId: String,
        viewId: String,
        _ body: ForkListViewRequest
    ) -> Request<ListViewResponse> {
        Request(
            method: .post,
            path: "/api/lists/\(listId)/views/\(viewId)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `PUT /api/lists/[id]/views/[viewId]` → `200 {"view":{…}}`.
    ///
    /// - Important: the `config` it carries **replaces** the stored one whole;
    ///   see `UpdateListViewRequest`.
    public static func updateView(
        listId: String,
        viewId: String,
        _ body: UpdateListViewRequest
    ) -> Request<ListViewResponse> {
        Request(
            method: .put,
            path: "/api/lists/\(listId)/views/\(viewId)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `DELETE /api/lists/[id]/views/[viewId]` → `200 {"message":"View deleted"}`.
    ///
    /// Typed `EmptyResponse` because the body carries no view — the caller
    /// already knows which id it removed, and decoding a confirmation string
    /// would invite branching on server copy.
    public static func deleteView(listId: String, viewId: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/lists/\(listId)/views/\(viewId)", auth: .bearer)
    }
}
