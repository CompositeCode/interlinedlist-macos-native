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

/// The small confirmation envelope returned by the follow action endpoints
/// (`POST`/`DELETE /api/follow/[userId]`, approve/reject/remove). Both keys are
/// optional so the type decodes whether the server returns `{ "success": true }`,
/// `{ "message": "…" }`, or `{}`.
public struct FollowActionResponse: Codable, Sendable, Equatable {
    public let success: Bool?
    public let message: String?

    public init(success: Bool? = nil, message: String? = nil) {
        self.success = success
        self.message = message
    }
}
