import Foundation
import InterlinedKit

// MARK: - Profile / Social DTO → domain mapping
//
// Sibling to `ListMappers.swift` — per-group slice of the audit-in-one-place
// mapper convention (PLAN.md §3). The follow/profile surface combines two
// kit DTOs (`FollowUserDTO`, `FollowCountsDTO`) and is stitched into the
// domain `UserProfile` by `SocialService`.

extension UserSummary {
    /// Maps the Follow group's bare-bones user shape. `displayName` falls back
    /// to `username` so the UI always has something to render; if neither is
    /// present (the API reference allows both to be optional on this DTO) we
    /// fall back to the id rather than crash.
    public init(from dto: FollowUserDTO) {
        let username = dto.username ?? dto.id
        self.init(
            id: dto.id,
            username: username,
            displayName: dto.displayName ?? username,
            avatarURL: dto.avatarUrl.flatMap(URL.init(string:))
        )
    }
}

extension UserProfile {
    /// Builds a public profile from the authenticated-account DTO. Used when
    /// the only profile data the client has is the signed-in user's own
    /// `GET /api/user` payload — viewing your own profile through the same
    /// projection the public view uses.
    ///
    /// The dedicated public-profile API endpoint (`GET /api/users/[username]`)
    /// is not yet exposed by the kit; see the M1 task 1B report for the
    /// follow-up kit work needed to surface other users' profiles by
    /// username.
    public init(from dto: UserDTO) {
        let summary = UserSummary(
            id: dto.id,
            username: dto.username,
            displayName: dto.displayName ?? dto.username,
            avatarURL: dto.avatar.flatMap(URL.init(string:))
        )
        self.init(
            summary: summary,
            bio: dto.bio,
            followerCount: nil,
            followingCount: nil,
            isPrivate: dto.isPrivateAccount ?? false,
            joinedAt: dto.createdAt
        )
    }

    /// Returns a copy with the counts populated — used by `SocialService` to
    /// stitch the identity payload together with the `/api/follow/[id]/counts`
    /// response without making the model mutable.
    public func withCounts(_ counts: FollowCountsDTO) -> UserProfile {
        UserProfile(
            summary: summary,
            bio: bio,
            followerCount: counts.followerCount,
            followingCount: counts.followingCount,
            isPrivate: isPrivate,
            joinedAt: joinedAt
        )
    }

    /// Projects a `UserProfile` from the embedded author on a `MessageDTO`,
    /// the reduced-scope fallback used by `SocialService.profile(username:)`
    /// (decision 0002 — public-profile fallback).
    ///
    /// The embedded author shape (`UserSummaryDTO`) carries only identity:
    /// `id`, `username`, `displayName`, `avatar`. Everything richer on
    /// `UserProfile` (`bio`, `followerCount`, `followingCount`, `joinedAt`)
    /// is unavailable from this source and is therefore left **definitely
    /// nil** until an upstream profile endpoint exists; `isPrivate` defaults
    /// to `false` for the same reason (we cannot know without an account
    /// payload, and assuming "public" matches the source — the user clearly
    /// has at least one public message). Callers needing follower / following
    /// counts must call `SocialService.counts(of:)` separately once the
    /// `id` from this projection is known.
    public init(fromEmbeddedAuthorOf message: MessageDTO) {
        let dto = message.user
        let summary = UserSummary(
            id: dto.id,
            username: dto.username,
            displayName: dto.displayName ?? dto.username,
            avatarURL: dto.avatar.flatMap(URL.init(string:))
        )
        self.init(
            summary: summary,
            bio: nil,
            followerCount: nil,
            followingCount: nil,
            isPrivate: false,
            joinedAt: nil
        )
    }
}

extension UsersPage {
    /// Maps the bare-array shape `GET /api/follow/[userId]/followers` and
    /// `/following` return today. The cursor fields default to "no more",
    /// matching the bare-array reality; if the kit later switches these to
    /// `Paginated<FollowUserDTO>` a sibling initializer can be added without
    /// changing call sites.
    public init(from dtos: [FollowUserDTO]) {
        self.init(
            users: dtos.map(UserSummary.init(from:)),
            hasMore: false,
            nextOffset: nil
        )
    }
}
