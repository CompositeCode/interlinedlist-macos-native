import Foundation

// MARK: - PublicProfileDTO (work-consolidation.md D2)
//
// `GET /api/users/{username}` — the public profile of any user by handle.
// Shape verified live 2026-07-31 (read-only). This endpoint did not exist when
// decision 0002 introduced the embedded-author fallback; it now does, and is
// strictly richer (bio, join date, private flag, follower/following counts).

public struct PublicProfileDTO: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatar: String?
    public let headerImage: String?
    public let bio: String?
    public let joinedAt: Date?
    public let isPrivate: Bool?
    public let followerCount: Int?
    public let followingCount: Int?
    public let publicMessageCount: Int?
    public let publicListCount: Int?

    public init(
        id: String,
        username: String,
        displayName: String? = nil,
        avatar: String? = nil,
        headerImage: String? = nil,
        bio: String? = nil,
        joinedAt: Date? = nil,
        isPrivate: Bool? = nil,
        followerCount: Int? = nil,
        followingCount: Int? = nil,
        publicMessageCount: Int? = nil,
        publicListCount: Int? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.headerImage = headerImage
        self.bio = bio
        self.joinedAt = joinedAt
        self.isPrivate = isPrivate
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.publicMessageCount = publicMessageCount
        self.publicListCount = publicListCount
    }
}
