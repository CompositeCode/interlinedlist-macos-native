import Foundation

/// Follower and following counts for a user, as the M1 profile header (and the
/// M5 social UIs) render them (PLAN.md §1 "Follow system").
///
/// This is the domain projection of `InterlinedKit.FollowCountsDTO`. It exists
/// so App-layer files never have to `import InterlinedKit` to display
/// follower counts (decision 0003 — App-layer Kit-import policy). The mapping
/// is total and lossless — the DTO has exactly these two fields — but
/// modelling the value here keeps the layering rule intact: the Domain layer
/// is the App's vocabulary; the DTO never crosses into the UI.
public struct FollowCounts: Sendable, Equatable, Hashable {

    /// Number of accounts that follow this user.
    public let followers: Int

    /// Number of accounts this user follows.
    public let following: Int

    public init(followers: Int, following: Int) {
        self.followers = followers
        self.following = following
    }

    /// Compatibility alias — the DTO uses `followerCount`. Kept as a computed
    /// property so existing view code that read `.followerCount` against the
    /// DTO continues to compile against the domain value without ceremony.
    public var followerCount: Int { followers }

    /// Compatibility alias — the DTO uses `followingCount`. See `followerCount`.
    public var followingCount: Int { following }

    /// The boundary value — a brand-new account with no follow relationships.
    public static let zero = FollowCounts(followers: 0, following: 0)
}
