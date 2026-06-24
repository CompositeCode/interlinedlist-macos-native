import Foundation

/// The caller's relationship to another user as the M5 profile UI renders it
/// (PLAN.md §1 "Follow system", §6 M5).
///
/// Domain projection of `InterlinedKit.FollowStatusDTO`. The DTO carries
/// three booleans (`following`, `followedBy`, `pendingRequest`); the domain
/// shape preserves all three but exposes a single derived `state` enum so the
/// follow button can be a one-switch render rather than a nested-if. The
/// existing `SocialServicing.status(of:)` method still returns the DTO for
/// back-compat with Wave 2 view code; new M5 surfaces should prefer this
/// domain value.
public struct FollowRelationship: Sendable, Equatable, Hashable {

    /// Is the caller currently following this user (approved)?
    public let isFollowing: Bool

    /// Is this user following the caller (the inverse direction)?
    public let isFollowedBy: Bool

    /// Has the caller sent a follow request that is still pending (private
    /// account, awaiting approval)?
    public let hasPendingRequest: Bool

    public init(
        isFollowing: Bool,
        isFollowedBy: Bool,
        hasPendingRequest: Bool
    ) {
        self.isFollowing = isFollowing
        self.isFollowedBy = isFollowedBy
        self.hasPendingRequest = hasPendingRequest
    }

    /// The derived state the follow button renders.
    public enum State: Sendable, Equatable, Hashable {
        /// Not following, no pending request — button reads "Follow".
        case notFollowing
        /// A request has been sent and is awaiting approval — button reads
        /// "Requested".
        case pending
        /// Currently following — button reads "Following" / "Unfollow".
        case following
    }

    /// Folds the three flags into the button state the UI binds to.
    public var state: State {
        if isFollowing { return .following }
        if hasPendingRequest { return .pending }
        return .notFollowing
    }

    /// Convenience: mutual follow — both directions are approved. Useful for
    /// the M5 "Friends" badge on a profile header.
    public var isMutual: Bool { isFollowing && isFollowedBy }
}

// MARK: - FollowAction

/// The typed outcome of a `follow(userId:)` call (PLAN.md §1 "Follow system /
/// request approval for private accounts", §6 M5).
///
/// `POST /api/follow/[userId]` returns either an approved follow (the target
/// is public, the relationship is live) or a queued request (the target is
/// private, approval is pending). The API surfaces this difference in the
/// `message` field of `FollowActionResponse`, which is unreliable to switch
/// on — different deployments phrase the message differently. The domain
/// layer infers the result from the relationship state immediately after the
/// call instead, and surfaces it here so the App layer renders the right
/// confirmation copy without re-fetching.
public enum FollowAction: Sendable, Equatable, Hashable {

    /// The follow is live — the caller is now following the target.
    case approved

    /// The target is a private account; the follow request is pending the
    /// target's approval.
    case pending
}
