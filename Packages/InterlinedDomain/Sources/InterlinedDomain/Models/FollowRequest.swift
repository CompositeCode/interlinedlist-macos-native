import Foundation

/// One pending inbound follow request — the M5 "Requests" tray entry surfaced
/// by `GET /api/follow/requests` (PLAN.md §1 "Follow system / request approval
/// for private accounts", §6 M5).
///
/// Domain projection of `InterlinedKit.FollowUserDTO` when that DTO is
/// surfaced from the `requests` envelope (the same shape carries follower /
/// following rows; the `status` field is `"pending"` here). Modelled as a
/// dedicated value type rather than a thin `UserSummary` alias so the App
/// layer can:
///
/// - render an approve / reject action explicitly (an approval workflow is a
///   different UX from the timeline's "who is this person" affordance);
/// - sort the inbox by `createdAt` without re-walking a parallel array.
///
/// Per decision 0003 the DTO does not cross into the UI — `SocialService`
/// returns `[FollowRequest]` and the App layer consumes domain values only.
public struct FollowRequest: Sendable, Equatable, Hashable, Identifiable {

    /// The follow-row id (the inbound `followId` on the DTO, falling back to
    /// the user's id when the server omits one). `Identifiable` so SwiftUI's
    /// `ForEach` can drive the inbox list without an explicit `id:` key.
    public let id: String

    /// The user who requested the follow.
    public let user: UserSummary

    /// When the request was created. `nil` only when the server omits it
    /// (defensive — every live response we have seen carries it).
    public let createdAt: Date?

    public init(id: String, user: UserSummary, createdAt: Date?) {
        self.id = id
        self.user = user
        self.createdAt = createdAt
    }
}
