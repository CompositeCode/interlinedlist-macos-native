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
}
