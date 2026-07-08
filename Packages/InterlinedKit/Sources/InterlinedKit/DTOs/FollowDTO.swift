import Foundation

// MARK: - FollowUserDTO

/// A user as surfaced by the Follow group's follower / following / requests
/// list endpoints. Shape verified against the live API on 2026-06-24:
/// `{ id, username, displayName, avatar, followId, createdAt }` plus a
/// `status` field on the `followers` / `following` rows (`"approved"` |
/// `"pending"`). `id` is the only field guaranteed non-nil; the rest are
/// modelled as optional for forward compatibility.
public struct FollowUserDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let avatar: String?
    public let followId: String?
    public let createdAt: Date?
    public let status: String?

    public init(
        id: String,
        username: String? = nil,
        displayName: String? = nil,
        avatar: String? = nil,
        followId: String? = nil,
        createdAt: Date? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.followId = followId
        self.createdAt = createdAt
        self.status = status
    }
}

// MARK: - FollowStatusDTO

/// `GET /api/follow/[userId]/status` — the caller's relationship to a user.
public struct FollowStatusDTO: Codable, Sendable, Equatable {
    public let following: Bool
    public let followedBy: Bool
    public let pendingRequest: Bool

    public init(following: Bool, followedBy: Bool, pendingRequest: Bool) {
        self.following = following
        self.followedBy = followedBy
        self.pendingRequest = pendingRequest
    }
}

// MARK: - FollowCountsDTO

/// `GET /api/follow/[userId]/counts`.
public struct FollowCountsDTO: Codable, Sendable, Equatable {
    public let followerCount: Int
    public let followingCount: Int

    public init(followerCount: Int, followingCount: Int) {
        self.followerCount = followerCount
        self.followingCount = followingCount
    }
}

// MARK: - FollowMutualCountsDTO

/// `GET /api/follow/[userId]/mutual` — **counts**, not a list. Shape verified
/// against the live API on 2026-06-24: `{ mutualFollowers, mutualFollowing }`.
/// Wave 1 had this typed as a list-of-users with optional count; that was
/// wrong. The Domain layer maps this into the appropriate `FollowCounts`-like
/// projection.
public struct FollowMutualCountsDTO: Codable, Sendable, Equatable {
    public let mutualFollowers: Int
    public let mutualFollowing: Int

    public init(mutualFollowers: Int, mutualFollowing: Int) {
        self.mutualFollowers = mutualFollowers
        self.mutualFollowing = mutualFollowing
    }
}

// MARK: - FollowRequestsResponse

/// `GET /api/follow/requests` — pending inbound follow requests. Shape
/// verified against the live API on 2026-06-24: `{ requests: [...] }`. No
/// pagination wrapper today — the route returns all pending requests.
/// (Backend ask filed: add pagination here so this endpoint matches the
/// `{ followers, pagination }` / `{ following, pagination }` shape used by
/// the sibling list endpoints.)
public struct FollowRequestsResponse: Codable, Sendable, Equatable {
    public let requests: [FollowUserDTO]

    public init(requests: [FollowUserDTO]) {
        self.requests = requests
    }
}

// MARK: - FollowActionResponse

/// The confirmation envelope returned by the follow action endpoints
/// (`POST /api/follow/[userId]`, `DELETE /api/follow/[userId]`, approve/reject/
/// remove). Shape verified 2026-07-07:
/// `{ "follow": { "status": "active" | "pending" } }`.
///
/// `"active"` means the follow is live (public account, relationship
/// immediately approved). `"pending"` means a request was queued (private
/// account, awaiting the target's approval).
///
/// `follow` is optional so that unfollow/approve/reject/remove responses
/// (which may omit this key) still decode without error. The domain mapper
/// treats a nil or absent `follow` as `.pending` — the safe conservative
/// default.
///
/// Note: `followedBy` is NOT included in the action response. A separate
/// `GET /api/follow/[userId]/status` call is still required when the caller
/// needs the inverse direction. Remove this note when the backend adds
/// `followedBy` to the follow action response.
public struct FollowActionResponse: Codable, Sendable, Equatable {

    /// The nested follow-status object. Absent on action endpoints that do not
    /// return a relationship snapshot (e.g. unfollow, approve, reject, remove).
    public let follow: FollowStatus?

    public init(follow: FollowStatus? = nil) {
        self.follow = follow
    }

    /// The nested `{ "status": "active" | "pending" }` object inside the
    /// follow action envelope.
    public struct FollowStatus: Codable, Sendable, Equatable {
        /// `"active"` — relationship is live. `"pending"` — awaiting approval.
        public let status: String

        public init(status: String) {
            self.status = status
        }
    }
}
