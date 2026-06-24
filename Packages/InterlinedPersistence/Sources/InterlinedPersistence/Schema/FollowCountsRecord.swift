import Foundation
import SwiftData

/// SwiftData record for cached follow counts on a profile (PLAN.md §1
/// "Follow system", §5 stale-while-revalidate, §6 M5).
///
/// One row per user id. Stores the public `FollowCounts` aggregates and the
/// `MutualCounts` aggregates the M5 profile header renders, so the profile
/// view paints instantly before the network refresh lands. `fetchedAt`
/// drives the "Last updated …" indicator and a TTL refresh policy (the
/// store does not enforce TTL itself — that is a service-layer decision).
///
/// Mutual counts default to 0 so a freshly-cached `FollowCounts`-only row
/// can be written without two writes; the boundary value is meaningful
/// (zero mutuals is the brand-new-account state).
///
/// Internal to the package: `SwiftDataFollowCountsStore` consumers see
/// only `FollowCountsRecord`-derived value types across the actor boundary.
@Model
final class FollowCountsRecord {

    @Attribute(.unique) var userID: String

    var followers: Int
    var following: Int
    var mutualFollowers: Int
    var mutualFollowing: Int
    var fetchedAt: Date

    init(
        userID: String,
        followers: Int = 0,
        following: Int = 0,
        mutualFollowers: Int = 0,
        mutualFollowing: Int = 0,
        fetchedAt: Date = Date()
    ) {
        self.userID = userID
        self.followers = followers
        self.following = following
        self.mutualFollowers = mutualFollowers
        self.mutualFollowing = mutualFollowing
        self.fetchedAt = fetchedAt
    }
}
