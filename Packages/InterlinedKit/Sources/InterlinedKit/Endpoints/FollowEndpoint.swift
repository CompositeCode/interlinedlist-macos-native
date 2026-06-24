import Foundation

/// Request builders for the **Follow / Social** API group — follow/unfollow,
/// relationship status, follower/following/mutual counts, follower/following
/// lists, request approval workflow (private accounts), and the pending-
/// requests inbox.
///
/// Follows the `Request.swift` conventions: one `public enum` namespace,
/// factories returning `Request<DTO>`, explicit `AuthRequirement`, path-only
/// URLs, `RequestBody.json` where a body applies, and never throwing.
///
/// Auth: all `.bearer` (decision 0001 — Bearer works on the whole follow
/// surface despite the docs marking it session-only).
///
/// **Envelopes pinned by the 2026-06-24 live probe** (closes Wave 1 deviation 5):
///
/// - `followers` and `following` return `Paginated<FollowUserDTO>` with
///   `paginationKey: "followers"` / `"following"` and the standard
///   `pagination` block (`total, limit, offset, hasMore`).
/// - `mutual` returns `FollowMutualCountsDTO` (`{ mutualFollowers,
///   mutualFollowing }`) — counts only, not a list.
/// - `requests` returns `FollowRequestsResponse` (`{ requests: [...] }`)
///   with no pagination wrapper. Backend ask filed to add pagination so
///   this matches followers/following.
public enum Follow {

    // MARK: - Follow / unfollow

    /// `POST /api/follow/[userId]`
    public static func follow(userId: String) -> Request<FollowActionResponse> {
        Request(method: .post, path: "/api/follow/\(userId)", auth: .bearer)
    }

    /// `DELETE /api/follow/[userId]`
    public static func unfollow(userId: String) -> Request<FollowActionResponse> {
        Request(method: .delete, path: "/api/follow/\(userId)", auth: .bearer)
    }

    // MARK: - Relationship reads

    /// `GET /api/follow/[userId]/status`
    public static func status(userId: String) -> Request<FollowStatusDTO> {
        Request(method: .get, path: "/api/follow/\(userId)/status", auth: .bearer)
    }

    /// `GET /api/follow/[userId]/followers` — paginated list under the
    /// `followers` key. Supports `limit` (1–100, server default 50),
    /// `offset` (≥ 0), and an optional `status` filter (`approved` |
    /// `pending`).
    public static func followers(
        userId: String,
        limit: Int? = nil,
        offset: Int? = nil,
        status: String? = nil
    ) -> Request<Paginated<FollowUserDTO>> {
        Request(
            method: .get,
            path: "/api/follow/\(userId)/followers",
            query: [
                .int("limit", limit),
                .int("offset", offset),
                .string("status", status)
            ],
            auth: .bearer,
            paginationKey: "followers"
        )
    }

    /// `GET /api/follow/[userId]/following` — paginated list under the
    /// `following` key. Same query parameters as `followers`.
    public static func following(
        userId: String,
        limit: Int? = nil,
        offset: Int? = nil,
        status: String? = nil
    ) -> Request<Paginated<FollowUserDTO>> {
        Request(
            method: .get,
            path: "/api/follow/\(userId)/following",
            query: [
                .int("limit", limit),
                .int("offset", offset),
                .string("status", status)
            ],
            auth: .bearer,
            paginationKey: "following"
        )
    }

    /// `GET /api/follow/[userId]/counts`
    public static func counts(userId: String) -> Request<FollowCountsDTO> {
        Request(method: .get, path: "/api/follow/\(userId)/counts", auth: .bearer)
    }

    /// `GET /api/follow/[userId]/mutual` — bare counts envelope
    /// `{ mutualFollowers, mutualFollowing }`. Not a list.
    public static func mutual(userId: String) -> Request<FollowMutualCountsDTO> {
        Request(method: .get, path: "/api/follow/\(userId)/mutual", auth: .bearer)
    }

    // MARK: - Request workflow (private accounts)

    /// `POST /api/follow/[userId]/approve`
    public static func approve(userId: String) -> Request<FollowActionResponse> {
        Request(method: .post, path: "/api/follow/\(userId)/approve", auth: .bearer)
    }

    /// `POST /api/follow/[userId]/reject`
    public static func reject(userId: String) -> Request<FollowActionResponse> {
        Request(method: .post, path: "/api/follow/\(userId)/reject", auth: .bearer)
    }

    /// `POST /api/follow/[userId]/remove`
    public static func remove(userId: String) -> Request<FollowActionResponse> {
        Request(method: .post, path: "/api/follow/\(userId)/remove", auth: .bearer)
    }

    /// `GET /api/follow/requests` — pending inbound follow requests under the
    /// `requests` key, no pagination wrapper today. (Limit / offset accepted
    /// for forward compatibility; the server currently ignores them.)
    public static func requests(
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<FollowRequestsResponse> {
        Request(
            method: .get,
            path: "/api/follow/requests",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer
        )
    }
}
