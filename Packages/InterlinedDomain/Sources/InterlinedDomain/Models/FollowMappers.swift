import Foundation
import InterlinedKit

// MARK: - Follow DTO → domain mapping
//
// Sibling to `ProfileMappers.swift` and `ListMappers.swift` — the per-group
// slice of the audit-in-one-place mapper convention (PLAN.md §3). Owns the
// translation from `InterlinedKit.FollowCountsDTO` (a wire shape) to
// `FollowCounts` (the domain value the App layer renders).
//
// Per decision 0003 (App-layer Kit-import policy), the App layer no longer
// references the DTO directly — `SocialServicing.counts(of:)` returns
// `FollowCounts`, and this mapper is the one place that crosses the boundary.

extension FollowCounts {
    /// Maps the on-wire counts envelope to the domain value. The mapping is
    /// total and lossless: the DTO has exactly these two fields.
    public init(from dto: FollowCountsDTO) {
        self.init(followers: dto.followerCount, following: dto.followingCount)
    }
}

// MARK: - MutualCounts mapper

extension MutualCounts {
    /// Maps the bare mutual-counts envelope to the domain value. The mapping
    /// is total and lossless: the DTO has exactly these two fields. Verified
    /// against the live API on 2026-06-24 — the endpoint returns counts, not
    /// a list of users (Wave 1 deviation 5 closure).
    public init(from dto: FollowMutualCountsDTO) {
        self.init(
            mutualFollowers: dto.mutualFollowers,
            mutualFollowing: dto.mutualFollowing
        )
    }
}

// MARK: - FollowRelationship mapper

extension FollowRelationship {
    /// Maps the relationship-status envelope to the domain value. The DTO's
    /// three booleans become the domain shape's three flags; the derived
    /// `state` property is computed downstream.
    public init(from dto: FollowStatusDTO) {
        self.init(
            isFollowing: dto.following,
            isFollowedBy: dto.followedBy,
            hasPendingRequest: dto.pendingRequest
        )
    }
}

// MARK: - FollowRequest mapper

extension FollowRequest {
    /// Maps one row of the `GET /api/follow/requests` envelope to the domain
    /// value. The row shape is `FollowUserDTO` with `status == "pending"`;
    /// the row id is the inbound `followId` when present (so approve / reject
    /// can address the follow record directly) and falls back to the user's
    /// id otherwise.
    public init(from dto: FollowUserDTO) {
        self.init(
            id: dto.followId ?? dto.id,
            user: UserSummary(from: dto),
            createdAt: dto.createdAt
        )
    }
}
