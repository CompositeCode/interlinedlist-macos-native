import Foundation

/// Request builders for the **Search** endpoints (the-gaps.md G5) — full-text
/// search across the current user's messages, lists, and documents.
///
/// Each route is a sub-route of its resource, but the three are grouped in one
/// namespace because they share a shape (a `q` term plus optional pagination)
/// and one App surface — the global search field — fans out to all of them.
///
/// Paths + verbs verified live 2026-07-31 (authenticated Bearer probe):
/// - `GET /api/messages/search?q=…` — the live verb is **GET**; a `POST` to
///   this path returns `405 Method Not Allowed`.
/// - `GET /api/lists/search?q=…`
/// - `GET /api/documents/search?q=…`
///
/// Follows the `Request.swift` conventions: factories returning `Request<DTO>`,
/// explicit `.bearer` auth, path-only URLs, nil-skipping query items, never
/// throwing.
public enum Search {

    /// `GET /api/messages/search?q=<query>` — full-text search over the
    /// current user's messages. `limit`/`offset` are accepted for forward
    /// compatibility (the live route ignores absent values).
    public static func messages(
        query: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<MessageSearchResponse> {
        Request(
            method: .get,
            path: "/api/messages/search",
            query: [
                .string("q", query),
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer
        )
    }

    /// `GET /api/lists/search?q=<query>` — search the current user's lists by
    /// title or description.
    public static func lists(
        query: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<ListSearchResponse> {
        Request(
            method: .get,
            path: "/api/lists/search",
            query: [
                .string("q", query),
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer
        )
    }

    /// `GET /api/documents/search?q=<query>` — search the current user's
    /// documents by title or content.
    public static func documents(
        query: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<DocumentSearchResponse> {
        Request(
            method: .get,
            path: "/api/documents/search",
            query: [
                .string("q", query),
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer
        )
    }
}
