import Foundation

/// Request builders for the **Moderation** API group (work-consolidation.md G2) — block,
/// mute, and report users and messages.
///
/// Paths verified against the live `/help/api/moderation` docs and the
/// 2026-07-31 probe (`GET /api/user/blocks` / `GET /api/user/mutes` return 200).
/// The block/mute/report *write* actions are fire-and-forget from the client's
/// point of view — the domain service sends them via `sendVoid`, so their
/// response body is never decoded (hence the tolerant `ModerationAck` return).
///
/// Auth: all `.bearer` (the docs note session-or-Bearer; Bearer is verified for
/// the list reads and is the app's default transport).
public enum Moderation {

    // MARK: - Lists

    /// `GET /api/user/blocks` — the users the current account blocks.
    public static func blocks(limit: Int? = nil, offset: Int? = nil) -> Request<BlockedUsersResponse> {
        Request(
            method: .get,
            path: "/api/user/blocks",
            query: [.int("limit", limit), .int("offset", offset)],
            auth: .bearer
        )
    }

    /// `GET /api/user/mutes` — the users the current account mutes.
    public static func mutes(limit: Int? = nil, offset: Int? = nil) -> Request<MutedUsersResponse> {
        Request(
            method: .get,
            path: "/api/user/mutes",
            query: [.int("limit", limit), .int("offset", offset)],
            auth: .bearer
        )
    }

    // MARK: - Block / unblock

    /// `POST /api/users/{username}/block` — block a user (mutual invisibility
    /// in feeds, search, threads, and DM eligibility).
    public static func block(username: String) -> Request<ModerationAck> {
        Request(method: .post, path: "/api/users/\(username)/block", auth: .bearer)
    }

    /// `DELETE /api/users/{username}/block` — unblock a user.
    public static func unblock(username: String) -> Request<ModerationAck> {
        Request(method: .delete, path: "/api/users/\(username)/block", auth: .bearer)
    }

    // MARK: - Mute / unmute

    /// `POST /api/users/{username}/mute` — mute a user (hide their content
    /// without the mutual invisibility of a block).
    public static func mute(username: String) -> Request<ModerationAck> {
        Request(method: .post, path: "/api/users/\(username)/mute", auth: .bearer)
    }

    /// `DELETE /api/users/{username}/mute` — unmute a user.
    public static func unmute(username: String) -> Request<ModerationAck> {
        Request(method: .delete, path: "/api/users/\(username)/mute", auth: .bearer)
    }

    // MARK: - Report

    /// `POST /api/users/{username}/report` — report a user with a reason and
    /// optional free-text detail.
    public static func reportUser(
        username: String,
        reason: String,
        detail: String? = nil
    ) -> Request<ModerationAck> {
        Request(
            method: .post,
            path: "/api/users/\(username)/report",
            body: .json(ReportRequest(reason: reason, detail: detail)),
            auth: .bearer
        )
    }

    /// `POST /api/messages/{id}/report` — report a message with a reason and
    /// optional free-text detail.
    public static func reportMessage(
        id: String,
        reason: String,
        detail: String? = nil
    ) -> Request<ModerationAck> {
        Request(
            method: .post,
            path: "/api/messages/\(id)/report",
            body: .json(ReportRequest(reason: reason, detail: detail)),
            auth: .bearer
        )
    }
}
