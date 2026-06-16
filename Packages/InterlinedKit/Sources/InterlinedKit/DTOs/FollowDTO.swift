import Foundation

// MARK: - FollowUserDTO

/// A user as surfaced by the Follow group's follower/following/mutual lists.
///
/// Deliberately a **group-local, minimal** user shape (not the kit-wide user
/// model, which is owned by another group) so this file is self-contained and
/// merge-clean. The Domain layer maps it onto the canonical user model. Only
/// `id` is required; the rest are optional because the API reference does not
/// pin every field on these list rows.
public struct FollowUserDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let avatarUrl: String?

    public init(
        id: String,
        username: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
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

// MARK: - FollowMutualDTO

/// `GET /api/follow/[userId]/mutual` — mutual-follow users plus a count. The
/// API reference does not pin the exact shape; modelled tolerantly with an
/// optional users array and count so decoding is resilient.
public struct FollowMutualDTO: Codable, Sendable, Equatable {
    public let mutual: [FollowUserDTO]?
    public let count: Int?

    public init(mutual: [FollowUserDTO]? = nil, count: Int? = nil) {
        self.mutual = mutual
        self.count = count
    }
}

// MARK: - FollowRequestDTO

/// A pending follow request from `GET /api/follow/requests`. Tolerant fields:
/// the requesting user plus optional metadata.
public struct FollowRequestDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let userId: String?
    public let username: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let createdAt: Date?

    public init(
        id: String,
        userId: String? = nil,
        username: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
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
