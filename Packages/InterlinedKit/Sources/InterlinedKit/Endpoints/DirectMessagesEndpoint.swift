import Foundation

/// Request builders for the **Direct Messages** API group (work-consolidation.md G1) —
/// private 1:1 conversations between mutual followers. Free tier (no
/// subscription required), including image attachments.
///
/// Paths + shapes verified live 2026-07-31 (authorized recon DM, then trashed).
/// Follows the `Request.swift` conventions: factories returning `Request<DTO>`,
/// explicit `.bearer` auth, path-only URLs, nil-skipping query items.
public enum DirectMessages {

    /// `GET /api/dm?folder=inbox|sent|deleted&cursor=…` — one folder listing,
    /// cursor-paginated. `folder` defaults to the inbox.
    public static func folder(_ folder: String = "inbox", cursor: String? = nil) -> Request<DMFolderPage> {
        Request(
            method: .get,
            path: "/api/dm",
            query: [.string("folder", folder), .string("cursor", cursor)],
            auth: .bearer
        )
    }

    /// `POST /api/dm` — send a direct message. Returns the created message
    /// wrapped under `message` (201).
    public static func send(_ body: SendDirectMessageRequest) -> Request<DMCreateResponse> {
        Request(method: .post, path: "/api/dm", body: .json(body), auth: .bearer)
    }

    /// `GET /api/dm/conversations?cursor=…` — the **real inbox**: one row per
    /// conversation, grouped server-side by `pairKey`, newest first
    /// (work-consolidation.md G22).
    ///
    /// This is a correctness improvement over collapsing a `folder("inbox")`
    /// page client-side: that grouping is only ever as complete as the page
    /// fetched, so a conversation whose newest message falls off the end of the
    /// page is simply invisible. This route has its own cursor and no such
    /// failure mode.
    ///
    /// Verified live 2026-09-09: 200 `{"items":[],"nextCursor":null}`; accepts
    /// Bearer; `OPTIONS` reports `GET, HEAD, OPTIONS`. The listing was empty on
    /// the test account, so `DMConversationDTO` decodes permissively.
    public static func conversations(cursor: String? = nil) -> Request<DMConversationsPage> {
        Request(
            method: .get,
            path: "/api/dm/conversations",
            query: [.string("cursor", cursor)],
            auth: .bearer
        )
    }

    /// `GET /api/dm/{id}` — one message by id, the deep-link target
    /// (work-consolidation.md G22).
    ///
    /// Verified live 2026-09-09: an unknown id answers 404
    /// `{"error":"Message not found.","code":"not_found"}`, and `OPTIONS`
    /// reports `GET, HEAD, OPTIONS`. The 200 envelope could not be captured
    /// (empty test account, writes not permitted), so `DMMessageResponse`
    /// accepts `{message}`, `{data}`, and the bare object.
    public static func message(id: String) -> Request<DMMessageResponse> {
        Request(method: .get, path: "/api/dm/\(id)", auth: .bearer)
    }

    /// `GET /api/dm/thread/{username}` — the conversation with `username`
    /// (chronological). Opening a thread marks received-unread messages read.
    public static func thread(username: String, cursor: String? = nil) -> Request<DMThreadResponse> {
        Request(
            method: .get,
            path: "/api/dm/thread/\(username)",
            query: [.string("cursor", cursor)],
            auth: .bearer
        )
    }

    /// `GET /api/dm/thread/{username}/updates` — lightweight incremental fetch
    /// for near-real-time polling. Same envelope as `thread`.
    public static func threadUpdates(username: String, since: String? = nil) -> Request<DMThreadResponse> {
        Request(
            method: .get,
            path: "/api/dm/thread/\(username)/updates",
            query: [.string("since", since)],
            auth: .bearer
        )
    }

    /// `GET /api/dm/recipients` — the users the current account may DM (mutual
    /// followers, not blocked).
    public static func recipients() -> Request<DMRecipientsResponse> {
        Request(method: .get, path: "/api/dm/recipients", auth: .bearer)
    }

    /// `GET /api/dm/unread-count` — total unread received DMs across all threads.
    public static func unreadCount() -> Request<DMUnreadCountResponse> {
        Request(method: .get, path: "/api/dm/unread-count", auth: .bearer)
    }

    /// `POST /api/dm/{id}/read` — mark a received message read (recipient-scoped).
    public static func markRead(id: String) -> Request<DMActionResponse> {
        Request(method: .post, path: "/api/dm/\(id)/read", auth: .bearer)
    }

    /// `POST /api/dm/{id}/trash` — soft-delete the caller's own side.
    public static func trash(id: String) -> Request<DMActionResponse> {
        Request(method: .post, path: "/api/dm/\(id)/trash", auth: .bearer)
    }

    /// `POST /api/dm/{id}/restore` — undo the caller's own soft-delete.
    public static func restore(id: String) -> Request<DMActionResponse> {
        Request(method: .post, path: "/api/dm/\(id)/restore", auth: .bearer)
    }

    // MARK: - Media uploads

    /// `POST /api/dm/images/upload` — upload one photo and receive its hosted
    /// URL, to be passed back in `SendDirectMessageRequest.imageUrls`
    /// (work-consolidation.md G22).
    ///
    /// Mirrors `Messages.uploadImage`: the caller supplies already-prepared
    /// bytes plus their MIME type, so the body is `RequestBody.raw`. The
    /// response reuses `MediaUploadResponse` (`{ "url": … }`).
    ///
    /// Verified live 2026-09-09 by method probe only: `OPTIONS` reports
    /// `OPTIONS, POST` and a `GET` answers 405. No upload was performed — the
    /// test account is shared and the probe budget is read-only.
    ///
    /// Sending photos requires a **verified email address**; the server
    /// answers 403 with the explanation when it is not. That refusal is
    /// surfaced verbatim — see `DirectMessagesService.uploadImage`.
    public static func uploadImage(_ data: Data, contentType: String) -> Request<MediaUploadResponse> {
        Request(
            method: .post,
            path: "/api/dm/images/upload",
            body: .raw(data, contentType: contentType),
            auth: .bearer
        )
    }
}
