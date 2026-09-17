import Foundation

/// A public user profile as the M1 read-only profile UI renders it (PLAN.md
/// §1 "Follow system" / "Profile & account", §6 M1).
///
/// This is the *public* projection — the fields any signed-in viewer can see
/// of another user. The `CurrentUser` model carries the additional account-
/// only fields (email, pending email, subscriber status, API keys).
///
/// The profile combines two API sources: a public user lookup (identity,
/// bio, avatar, account flags) and `GET /api/follow/[userId]/counts` for the
/// follower/following totals. The owning `SocialService` is responsible for
/// stitching them together so the view sees one model.
public struct UserProfile: Sendable, Equatable, Hashable, Identifiable {
    /// The compact identity shared with the message-card projection. Reusing
    /// `UserSummary` keeps avatar handling and display-name fallback in one
    /// place across the app.
    public let summary: UserSummary
    /// The user's bio / about line. `nil` when unset.
    public let bio: String?
    /// Total followers, when the API surfaced the counts call. `nil` when the
    /// stitch was skipped (e.g. counts call failed but identity succeeded).
    public let followerCount: Int?
    /// Total accounts this user follows. `nil` for the same reason as above.
    public let followingCount: Int?
    /// When set, the account is private — follow requests require approval
    /// before posts become visible (PLAN.md §1 "Follow system" / "request
    /// approval for private accounts").
    public let isPrivate: Bool
    /// Account creation timestamp, when the API returns it.
    public let joinedAt: Date?

    // MARK: Content counts (GitHub #44 / G32)
    //
    // `GET /api/users/{username}` has always returned these; the domain model
    // dropped them at the boundary, so the header could only ever show two of
    // the web profile's five stat tiles. Verified live 2026-09-15:
    //
    //   {"followerCount":1,"followingCount":1,
    //    "publicMessageCount":31,"publicListCount":0}

    /// Public posts this user has published. `nil` when the route did not
    /// supply it — which is **not** the same as zero, and the header renders
    /// the tile only when a real number is known.
    public let publicMessageCount: Int?

    /// Public lists this user owns. Same `nil` semantics as above.
    public let publicListCount: Int?

    /// The profile banner image, when set.
    public let headerImageURL: URL?

    public var id: String { summary.id }
    public var username: String { summary.username }
    public var displayName: String { summary.displayName }
    public var avatarURL: URL? { summary.avatarURL }

    public init(
        summary: UserSummary,
        bio: String? = nil,
        followerCount: Int? = nil,
        followingCount: Int? = nil,
        isPrivate: Bool = false,
        joinedAt: Date? = nil,
        publicMessageCount: Int? = nil,
        publicListCount: Int? = nil,
        headerImageURL: URL? = nil
    ) {
        self.summary = summary
        self.bio = bio
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.isPrivate = isPrivate
        self.joinedAt = joinedAt
        self.publicMessageCount = publicMessageCount
        self.publicListCount = publicListCount
        self.headerImageURL = headerImageURL
    }
}

/// One page of users from a follower / following lookup, mirroring the other
/// `*Page` shapes. The follow list endpoints currently return bare arrays
/// rather than the paginated envelope; the kit may switch them to
/// `Paginated<FollowUserDTO>` later (see `FollowEndpoint.swift` note). When
/// that happens the `hasMore` / `nextOffset` fields here will start carrying
/// real values; today they default to `false` / `nil`.
public struct UsersPage: Sendable, Equatable {
    public let users: [UserSummary]
    public let hasMore: Bool
    public let nextOffset: Int?

    public init(users: [UserSummary], hasMore: Bool = false, nextOffset: Int? = nil) {
        self.users = users
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// An empty page with no further results.
    public static let empty = UsersPage(users: [], hasMore: false, nextOffset: nil)
}
