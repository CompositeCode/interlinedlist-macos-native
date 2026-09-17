import Foundation

/// Request builders for **link metadata / rich previews**
/// (work-consolidation.md G21).
///
/// Three routes, all verified live 2026-09-07 against the `.env` test account:
///
/// | route | verb (`Allow`) | body |
/// |---|---|---|
/// | `/api/link-metadata?url=…` | `GET, HEAD, OPTIONS` | `{ "link": {…} }` |
/// | `/api/messages/{id}/metadata` | `GET, HEAD, OPTIONS, POST` | `{ "links": [...] }` |
/// | `/api/images/proxy?url=…` | `GET, HEAD, OPTIONS` | raw image bytes |
///
/// `GET /api/link-metadata` resolves a URL **without** persisting anything, so
/// it is the safe call for the composer to make while the user is still typing.
/// `POST /api/messages/{id}/metadata` is the persisting counterpart: it fetches
/// and stores a message's link metadata server-side.
public enum LinkMetadata {

    /// `GET /api/link-metadata?url=…` — resolve one URL to a rich preview
    /// without persisting it.
    ///
    /// Omitting `url` answers `400 {"error":"Missing url","code":"bad_request"}`,
    /// so callers must pass a non-empty value. An unreachable host still answers
    /// `200` with `fetchStatus: "failed"` and no `metadata` — a failed *fetch*
    /// is not a failed *request*.
    public static func resolve(url: String) -> Request<LinkMetadataResponse> {
        Request(
            method: .get,
            path: "/api/link-metadata",
            query: [.string("url", url)],
            auth: .bearer
        )
    }

    /// `GET /api/messages/[id]/metadata` — the stored link metadata for one
    /// message.
    ///
    /// Answers the bare `{ "links": [...] }` object — no envelope key — which
    /// is exactly `LinkMetadataDTO`, the same type embedded on `MessageDTO`.
    /// Lightweight compared with re-fetching the whole message.
    public static func forMessage(id: String) -> Request<LinkMetadataDTO> {
        Request(method: .get, path: "/api/messages/\(id)/metadata", auth: .bearer)
    }

    /// `POST /api/messages/[id]/metadata` — fetch and **persist** this
    /// message's link metadata, returning the refreshed set.
    ///
    /// The route takes no body; the server derives the URLs from the message
    /// content. Use it to retry links whose `fetchStatus` came back `"failed"`.
    public static func refreshForMessage(id: String) -> Request<LinkMetadataDTO> {
        Request(method: .post, path: "/api/messages/\(id)/metadata", auth: .bearer)
    }

    /// `GET /api/images/proxy?url=…` — server-side image fetch.
    ///
    /// **Narrow by design:** the live route accepts *only* Instagram image URLs
    /// (any other host answers `403 {"error":"Only Instagram image URLs are
    /// allowed"}`) — it exists because Instagram's CDN blocks hotlinking, not
    /// as a general-purpose proxy. Verified 2026-09-07. When the Instagram
    /// fetch itself fails the route still answers `200` with a placeholder
    /// `image/svg+xml`, so a caller never has to handle a broken-image state.
    ///
    /// Returns the absolute `URL` to hand to `AsyncImage` rather than a
    /// `Request` — the response is image bytes, not JSON.
    /// See `LinkPreview.needsImageProxy` for the host test that decides whether
    /// a thumbnail should be routed through here.
    public static func imageProxyURL(baseURL: URL, imageURL: String) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/images/proxy"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "url", value: imageURL)]
        return components?.url
    }
}
