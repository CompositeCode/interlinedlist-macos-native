import Foundation

/// Request builders for the **Exports** API group — the four CSV export
/// endpoints (messages, lists, list data rows, follows).
///
/// Follows the `Request.swift` conventions: one `public enum` namespace,
/// factories returning `Request<…>`, explicit `AuthRequirement`, path-only
/// URLs, and never throwing.
///
/// **Auth: `.session` for all four** — these are the decision-0001
/// session-only allowlist endpoints (`/api/exports/*`). The lazy cookie
/// transport is established the first time a user runs an export.
///
/// **Response shape:** these endpoints return a CSV **file**, not JSON, so the
/// `Request` is typed `Request<EmptyResponse>` purely as a phantom type and is
/// executed via `APIClient.sendRaw(_:)`, which yields `(Data, contentType)`.
/// Wrap that tuple with `CSVExport.from(_:)` to get the bytes plus the
/// `text/csv` content type. Do not call `send(_:)` on these — there is no JSON
/// body to decode.
public enum Exports {

    /// `GET /api/exports/messages` — CSV export of the user's messages.
    public static func messages() -> Request<EmptyResponse> {
        Request(method: .get, path: "/api/exports/messages", auth: .session)
    }

    /// `GET /api/exports/lists` — CSV export of list definitions
    /// (title, description, schema).
    public static func lists() -> Request<EmptyResponse> {
        Request(method: .get, path: "/api/exports/lists", auth: .session)
    }

    /// `GET /api/exports/list-data-rows` — CSV export of row data across lists.
    public static func listDataRows() -> Request<EmptyResponse> {
        Request(method: .get, path: "/api/exports/list-data-rows", auth: .session)
    }

    /// `GET /api/exports/follows` — CSV export of follower/following
    /// relationships.
    public static func follows() -> Request<EmptyResponse> {
        Request(method: .get, path: "/api/exports/follows", auth: .session)
    }
}
