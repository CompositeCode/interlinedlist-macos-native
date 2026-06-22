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
