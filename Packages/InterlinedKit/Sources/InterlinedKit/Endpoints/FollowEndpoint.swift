import Foundation

/// Request builders for the **Follow / Social** API group — follow/unfollow,
/// relationship status, follower/following/mutual lists, counts, request
/// approval workflow (private accounts), and the pending-requests inbox.
///
/// Follows the `Request.swift` conventions: one `public enum` namespace,
/// factories returning `Request<DTO>`, explicit `AuthRequirement`, path-only
/// URLs, `RequestBody.json` where a body applies, and never throwing.
///
/// Auth: all `.bearer` (decision 0001 — Bearer works on the whole follow
/// surface despite the docs marking it session-only).
///
/// The follower/following/mutual list endpoints' exact envelope is not pinned
/// by the API reference; they are typed as bare arrays of `FollowUserDTO`,
/// which is the most common InterlinedList shape for these collections. If the
/// live API wraps them under `"data"` with a pagination envelope, switch the
/// return type to `Paginated<FollowUserDTO>` with `paginationKey: "data"` —
/// the builder signature is otherwise unchanged.
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

    /// `GET /api/follow/[userId]/followers`
    public static func followers(userId: String) -> Request<[FollowUserDTO]> {
        Request(method: .get, path: "/api/follow/\(userId)/followers", auth: .bearer)
    }

    /// `GET /api/follow/[userId]/following`
    public static func following(userId: String) -> Request<[FollowUserDTO]> {
        Request(method: .get, path: "/api/follow/\(userId)/following", auth: .bearer)
    }

    /// `GET /api/follow/[userId]/counts`
    public static func counts(userId: String) -> Request<FollowCountsDTO> {
        Request(method: .get, path: "/api/follow/\(userId)/counts", auth: .bearer)
    }

    /// `GET /api/follow/[userId]/mutual`
    public static func mutual(userId: String) -> Request<FollowMutualDTO> {
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

    /// `GET /api/follow/requests` — pending inbound follow requests. The API
    /// reference shows this wrapped in the `{ "data": [...], "pagination" }`
    /// envelope.
    public static func requests(
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<FollowRequestDTO>> {
        Request(
            method: .get,
            path: "/api/follow/requests",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer,
            paginationKey: "data"
        )
    }
}
