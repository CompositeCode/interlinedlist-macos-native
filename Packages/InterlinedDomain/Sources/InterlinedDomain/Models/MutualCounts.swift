import Foundation

/// Mutual-follow counts for a user (PLAN.md §1 "Follow system / mutuals",
/// §6 M5).
///
/// Domain projection of `InterlinedKit.FollowMutualCountsDTO`. The live API
/// verified 2026-06-24 returns **counts**, not a list of users
/// (`{ mutualFollowers, mutualFollowing }`). The M5 profile header renders
/// "X mutual followers / Y you both follow"; this value type carries exactly
/// that information.
///
/// Per decision 0003 the DTO does not cross into the UI — `SocialService`
/// returns `MutualCounts` and the App layer consumes domain values only.
public struct MutualCounts: Sendable, Equatable, Hashable {

    /// Accounts that follow both the caller and the target.
    public let mutualFollowers: Int

    /// Accounts the caller and the target both follow.
    public let mutualFollowing: Int

    public init(mutualFollowers: Int, mutualFollowing: Int) {
        self.mutualFollowers = mutualFollowers
        self.mutualFollowing = mutualFollowing
    }

    /// The boundary value — no mutual overlap in either direction.
    public static let zero = MutualCounts(mutualFollowers: 0, mutualFollowing: 0)
}
