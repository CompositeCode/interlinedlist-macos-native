import Foundation

// MARK: - MessageDTO

/// A single message (post) as returned by the Messages endpoints.
///
/// Mirrors the live API response verbatim (camelCase keys, no key conversion —
/// the shared `JSONCoders` decoder uses the default key strategy). Fields the
/// API may omit or send as `null` are modelled as Swift optionals.
///
/// `pushedMessage` is the recursively-nested repost target; the API returns the
/// full message object there when `pushedMessageId` is set.
public struct MessageDTO: Decodable, Sendable, Equatable {
    public let id: String
    public let content: String
    public let publiclyVisible: Bool
    public let userId: String
    public let parentId: String?
    public let linkMetadata: LinkMetadataDTO?
    public let imageUrls: [String]?
    public let videoUrls: [String]?
    public let crossPostUrls: [CrossPostURLDTO]?
    public let scheduledAt: Date?
    public let tags: [String]?
    public let createdAt: Date
    public let updatedAt: Date
    public let digCount: Int
    public let pushCount: Int
    public let pushedMessageId: String?
    public let user: UserSummaryDTO
    public let pushedMessage: PushedMessageBox?
    public let dugByMe: Bool
    public let crossPosts: [CrossPostResultDTO]?

    public init(
        id: String,
        content: String,
        publiclyVisible: Bool,
        userId: String,
        parentId: String? = nil,
        linkMetadata: LinkMetadataDTO? = nil,
        imageUrls: [String]? = nil,
        videoUrls: [String]? = nil,
        crossPostUrls: [CrossPostURLDTO]? = nil,
        scheduledAt: Date? = nil,
        tags: [String]? = nil,
        createdAt: Date,
        updatedAt: Date,
        digCount: Int,
        pushCount: Int,
        pushedMessageId: String? = nil,
        user: UserSummaryDTO,
        pushedMessage: PushedMessageBox? = nil,
        dugByMe: Bool,
        crossPosts: [CrossPostResultDTO]? = nil
    ) {
        self.id = id
        self.content = content
        self.publiclyVisible = publiclyVisible
        self.userId = userId
        self.parentId = parentId
        self.linkMetadata = linkMetadata
        self.imageUrls = imageUrls
        self.videoUrls = videoUrls
        self.crossPostUrls = crossPostUrls
        self.scheduledAt = scheduledAt
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.digCount = digCount
        self.pushCount = pushCount
        self.pushedMessageId = pushedMessageId
        self.user = user
        self.pushedMessage = pushedMessage
        self.dugByMe = dugByMe
        self.crossPosts = crossPosts
    }
}

// MARK: - PushedMessageBox

/// Indirection box for the recursively-nested repost target.
///
/// `MessageDTO` cannot hold an optional `MessageDTO` directly without an
/// `indirect` reference — a value type cannot contain itself by value. Wrapping
/// the nested message in a small reference-typed box (rather than `indirect
/// enum`) keeps `MessageDTO` a clean struct while breaking the size recursion.
public final class PushedMessageBox: Decodable, Sendable, Equatable {
    public let message: MessageDTO

    public init(_ message: MessageDTO) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.message = try container.decode(MessageDTO.self)
    }

    public static func == (lhs: PushedMessageBox, rhs: PushedMessageBox) -> Bool {
        lhs.message == rhs.message
    }
}

// MARK: - UserSummaryDTO

/// The compact author summary embedded in message responses
/// (`{ id, username, displayName, avatar }`). Distinct from the full
/// `UserDTO` returned by `GET /api/user`.
public struct UserSummaryDTO: Decodable, Sendable, Equatable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatar: String?

    public init(id: String, username: String, displayName: String? = nil, avatar: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
    }
}

// MARK: - LinkMetadataDTO

/// Server-rendered link previews attached to a message:
/// `{ "links": [{ url, platform, fetchStatus }] }`.
public struct LinkMetadataDTO: Decodable, Sendable, Equatable {
    public let links: [LinkPreviewDTO]

    public init(links: [LinkPreviewDTO]) {
        self.links = links
    }
}

/// A single resolved link preview entry.
public struct LinkPreviewDTO: Decodable, Sendable, Equatable {
    public let url: String
    public let platform: String?
    public let fetchStatus: String?
    public let title: String?
    public let description: String?
    public let imageUrl: String?

    public init(
        url: String,
        platform: String? = nil,
        fetchStatus: String? = nil,
        title: String? = nil,
        description: String? = nil,
        imageUrl: String? = nil
    ) {
        self.url = url
        self.platform = platform
        self.fetchStatus = fetchStatus
        self.title = title
        self.description = description
        self.imageUrl = imageUrl
    }
}

// MARK: - CrossPostURLDTO

/// A per-platform cross-post result attached to a published message.
/// Populated after the server fans the post out to Mastodon / Bluesky /
/// LinkedIn. `statusIds` carries the per-instance ids when a single platform
/// targets multiple instances (Mastodon).
public struct CrossPostURLDTO: Decodable, Sendable, Equatable {
    public let url: String
    public let platform: String
    public let statusId: String?
    public let statusIds: [String]?
    public let instanceUrl: String?
    public let instanceName: String?

    public init(
        url: String,
        platform: String,
        statusId: String? = nil,
        statusIds: [String]? = nil,
        instanceUrl: String? = nil,
        instanceName: String? = nil
    ) {
        self.url = url
        self.platform = platform
        self.statusId = statusId
        self.statusIds = statusIds
        self.instanceUrl = instanceUrl
        self.instanceName = instanceName
    }
}

// MARK: - CrossPostResultDTO

public struct CrossPostResultDTO: Decodable, Sendable, Equatable {
    public let platform: String
    public let providerId: String?
    public let status: String           // "ok" | "failed" | "pending"
    public let externalUrl: String?
    public let error: String?

    public init(
        platform: String,
        providerId: String? = nil,
        status: String,
        externalUrl: String? = nil,
        error: String? = nil
    ) {
        self.platform = platform
        self.providerId = providerId
        self.status = status
        self.externalUrl = externalUrl
        self.error = error
    }
}

// MARK: - CreateMessageRequest

/// Request body for `POST /api/messages` and `PUT /api/messages/[id]`.
///
/// The API's canonical content field is `content`; Markdown is authored inline
/// in that same field (the server renders it), so there is no separate
/// `markdown` key — `content` carries the Markdown source. `publiclyVisible`
/// is the visibility toggle.
///
/// Cross-post and scheduling fields are all optional and default to `nil`, so
/// a plain text post is `CreateMessageRequest(content: "hi")`. Optional fields
/// encode only when set (see `encode(to:)`), so the wire body stays minimal.
public struct CreateMessageRequest: Encodable, Sendable, Equatable {
    /// The message body. Markdown source is authored here; the server renders it.
    public let content: String
    /// Visibility toggle. `nil` lets the server apply the account default.
    public let publiclyVisible: Bool?
    public let tags: [String]?
    public let parentId: String?
    public let pushedMessageId: String?
    public let imageUrls: [String]?
    public let videoUrls: [String]?
    public let scheduledAt: Date?
    public let mastodonProviderIds: [String]?
    public let crossPostToBluesky: Bool?
    public let crossPostToLinkedIn: Bool?

    public init(
        content: String,
        publiclyVisible: Bool? = nil,
        tags: [String]? = nil,
        parentId: String? = nil,
        pushedMessageId: String? = nil,
        imageUrls: [String]? = nil,
        videoUrls: [String]? = nil,
        scheduledAt: Date? = nil,
        mastodonProviderIds: [String]? = nil,
        crossPostToBluesky: Bool? = nil,
        crossPostToLinkedIn: Bool? = nil
    ) {
        self.content = content
        self.publiclyVisible = publiclyVisible
        self.tags = tags
        self.parentId = parentId
        self.pushedMessageId = pushedMessageId
        self.imageUrls = imageUrls
        self.videoUrls = videoUrls
        self.scheduledAt = scheduledAt
        self.mastodonProviderIds = mastodonProviderIds
        self.crossPostToBluesky = crossPostToBluesky
        self.crossPostToLinkedIn = crossPostToLinkedIn
    }

    private enum CodingKeys: String, CodingKey {
        case content, publiclyVisible, tags, parentId, pushedMessageId
        case imageUrls, videoUrls, scheduledAt
        case mastodonProviderIds, crossPostToBluesky, crossPostToLinkedIn
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // `content` is required and always encoded; everything else is
        // skipped when nil so the server applies its own defaults.
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(publiclyVisible, forKey: .publiclyVisible)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(parentId, forKey: .parentId)
        try container.encodeIfPresent(pushedMessageId, forKey: .pushedMessageId)
        try container.encodeIfPresent(imageUrls, forKey: .imageUrls)
        try container.encodeIfPresent(videoUrls, forKey: .videoUrls)
        try container.encodeIfPresent(scheduledAt, forKey: .scheduledAt)
        try container.encodeIfPresent(mastodonProviderIds, forKey: .mastodonProviderIds)
        try container.encodeIfPresent(crossPostToBluesky, forKey: .crossPostToBluesky)
        try container.encodeIfPresent(crossPostToLinkedIn, forKey: .crossPostToLinkedIn)
    }
}

// MARK: - List envelopes

/// Response envelope for `GET /api/messages/[id]/replies`.
///
/// This endpoint does **not** use the standard `Paginated` envelope: the live
/// API returns `{ "replies": [...], "total": Int }` (no `limit`/`offset`/
/// `hasMore`). Modelled as its own DTO so the shape is honoured exactly.
public struct RepliesResponse: Decodable, Sendable, Equatable {
    public let replies: [MessageDTO]
    public let total: Int

    public init(replies: [MessageDTO], total: Int) {
        self.replies = replies
        self.total = total
    }
}

/// Response envelope for `GET /api/messages/scheduled`.
///
/// Also non-standard: the live API returns `{ "messages": [...] }` with no
/// `pagination` envelope.
public struct ScheduledMessagesResponse: Decodable, Sendable, Equatable {
    public let messages: [MessageDTO]

    public init(messages: [MessageDTO]) {
        self.messages = messages
    }
}

// MARK: - Action responses

/// Response for `POST`/`DELETE /api/messages/[id]/dig`.
///
/// `isNewDig` and `digCreatedAt` are present on the POST (add) response and
/// absent on the DELETE (remove) response, so both are optional.
public struct DigResponse: Decodable, Sendable, Equatable {
    public let digCount: Int
    public let dugByMe: Bool
    public let isNewDig: Bool?
    public let digCreatedAt: Date?

    public init(digCount: Int, dugByMe: Bool, isNewDig: Bool? = nil, digCreatedAt: Date? = nil) {
        self.digCount = digCount
        self.dugByMe = dugByMe
        self.isNewDig = isNewDig
        self.digCreatedAt = digCreatedAt
    }
}

/// Response for `POST /api/messages/images/upload` and
/// `POST /api/messages/videos/upload`: `{ "url": "string" }`.
public struct MediaUploadResponse: Decodable, Sendable, Equatable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}
