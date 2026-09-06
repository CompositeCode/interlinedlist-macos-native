import Foundation

/// Request builders for **tag trending + autocomplete** (work-consolidation.md
/// G20) — feeds the timeline's trending strip and the composer's tag-completion
/// popover.
///
/// `GET /api/tags/trending` has a verified response shape; `GET
/// /api/tags/autocomplete` does not, so its DTO decodes tolerantly (see
/// `TagSuggestionsResponse`).
public enum Tags {

    /// `GET /api/tags/trending` — most-used tags, newest usage first.
    ///
    /// - Parameter limit: optional server-side cap. Dropped when nil.
    public static func trending(limit: Int? = nil) -> Request<TrendingTagsResponse> {
        Request(
            method: .get,
            path: "/api/tags/trending",
            query: [.int("limit", limit)],
            auth: .bearer
        )
    }

    /// `GET /api/tags/autocomplete?q=…` — prefix match over public messages.
    ///
    /// The gap definition names the route as a prefix match but not its query
    /// key; `q` matches every other search route on this API
    /// (`/api/messages/search`, `/api/lists/search`, `/api/documents/search`).
    public static func autocomplete(prefix: String, limit: Int? = nil) -> Request<TagSuggestionsResponse> {
        Request(
            method: .get,
            path: "/api/tags/autocomplete",
            query: [.string("q", prefix), .int("limit", limit)],
            auth: .bearer
        )
    }
}
