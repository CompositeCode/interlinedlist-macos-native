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
/// `{ "links": [ …LinkPreviewDTO… ] }`.
///
/// This is also the **whole body** of `GET /api/messages/[id]/metadata`
/// (work-consolidation.md G21), which answers the bare `{ "links": [...] }`
/// object with no envelope key — verified live 2026-09-07.
public struct LinkMetadataDTO: Decodable, Sendable, Equatable {
    public let links: [LinkPreviewDTO]

    public init(links: [LinkPreviewDTO]) {
        self.links = links
    }
}

/// A single resolved link preview entry.
///
/// **Shape corrected 2026-09-07 (G21 live probe).** The server nests the
/// human-readable fields under a `metadata` object and names the image
/// `thumbnail` — not the flat `title` / `description` / `imageUrl` this type
/// previously declared:
///
/// ```json
/// { "url": "https://compositecode.blog/…",
///   "platform": "other",
///   "fetchStatus": "success",
///   "fetchedAt": "2026-09-06T21:34:31.989Z",
///   "metadata": { "type": "link", "ogType": "article",
///                 "title": "…", "description": "…", "thumbnail": "https://…" } }
/// ```
///
/// Because every flat field was optional, the old decode **succeeded** while
/// silently yielding `title`/`description`/`imageUrl` = `nil`; combined with
/// `fetchStatus: "success"` passing `LinkPreview.isFetchStatusReady`, every
/// link on the timeline rendered as a bordered card showing only its host. The
/// decoder below reads the nested shape and still falls back to the flat keys
/// (fixtures, stubs, and any older server build), mirroring the both-shapes
/// tolerance `MessageWriteResponse` uses for the create-envelope drift.
///
/// `fetchStatus` vocabulary observed live: `"success"` and `"failed"` (a failed
/// entry carries neither `metadata` nor `fetchedAt`).
/// `platform` vocabulary observed live: `"other"`, `"youtube"`, `"x"`,
/// `"bluesky"`, `"instagram"`.
public struct LinkPreviewDTO: Decodable, Sendable, Equatable {
    public let url: String
    public let platform: String?
    public let fetchStatus: String?
    public let fetchedAt: String?
    public let title: String?
    public let description: String?
    public let imageUrl: String?

    public init(
        url: String,
        platform: String? = nil,
        fetchStatus: String? = nil,
        fetchedAt: String? = nil,
        title: String? = nil,
        description: String? = nil,
        imageUrl: String? = nil
    ) {
        self.url = url
        self.platform = platform
        self.fetchStatus = fetchStatus
        self.fetchedAt = fetchedAt
        self.title = title
        self.description = description
        self.imageUrl = imageUrl
    }

    private enum CodingKeys: String, CodingKey {
        case url, platform, fetchStatus, fetchedAt, metadata
        // Flat fallbacks — the pre-2026-09-07 assumed shape, still emitted by
        // test fixtures and stubs.
        case title, description, imageUrl
    }

    /// The nested `metadata` object. `thumbnail` is the image key; `type` and
    /// `ogType` are carried for completeness but are not surfaced to the domain
    /// today.
    private struct Metadata: Decodable {
        let title: String?
        let description: String?
        let thumbnail: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.platform = try container.decodeIfPresent(String.self, forKey: .platform)
        self.fetchStatus = try container.decodeIfPresent(String.self, forKey: .fetchStatus)
        self.fetchedAt = try container.decodeIfPresent(String.self, forKey: .fetchedAt)

        // Live shape first; fall back to the flat keys so fixtures and any
        // older server build still decode. A `failed` entry has no `metadata`
        // object at all, which lands on the flat path and yields all-nil.
        let nested = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
        let flatTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let flatDescription = try container.decodeIfPresent(String.self, forKey: .description)
        let flatImageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)

        self.title = nested?.title ?? flatTitle
        self.description = nested?.description ?? flatDescription
        self.imageUrl = nested?.thumbnail ?? flatImageUrl
    }
}

// MARK: - LinkMetadataResponse

/// Response envelope for `GET /api/link-metadata?url=…` (G21).
///
/// Single-resource routes on this API answer `{ message?, <resource> }`; here
/// the resource key is `link` — verified live 2026-09-07:
/// `{"link":{"url":"…","platform":"other","metadata":{…},"fetchStatus":"success"}}`.
public struct LinkMetadataResponse: Decodable, Sendable, Equatable {
    public let link: LinkPreviewDTO

    public init(link: LinkPreviewDTO) {
        self.link = link
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

// MARK: - MessageDTO cross-post merge

public extension MessageDTO {

    /// Returns a copy of the message with its `crossPosts` results replaced.
    ///
    /// Used to fold the write-envelope's **top-level** `crossPosts` array into
    /// the message decoded from the envelope's `data` object (see
    /// `MessageWriteResponse`) — the wrapped `data` object carries only
    /// `crossPostUrls`, while the parsed per-platform results live one level up.
    /// A `nil` / empty argument leaves the message untouched.
    func mergingCrossPosts(_ crossPosts: [CrossPostResultDTO]?) -> MessageDTO {
        guard let crossPosts, !crossPosts.isEmpty else { return self }
        return MessageDTO(
            id: id,
            content: content,
            publiclyVisible: publiclyVisible,
            userId: userId,
            parentId: parentId,
            linkMetadata: linkMetadata,
            imageUrls: imageUrls,
            videoUrls: videoUrls,
            crossPostUrls: crossPostUrls,
            scheduledAt: scheduledAt,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            digCount: digCount,
            pushCount: pushCount,
            pushedMessageId: pushedMessageId,
            user: user,
            pushedMessage: pushedMessage,
            dugByMe: dugByMe,
            crossPosts: crossPosts
        )
    }
}

// MARK: - MessageWriteResponse

/// Response wrapper for the message **write** endpoints (`POST /api/messages`,
/// `PUT /api/messages/[id]`).
///
/// Drift observed live 2026-08-17: the create endpoint no longer returns a flat
/// `MessageDTO`. It wraps the created/updated message under a `data` key and
/// reports the cross-post fan-out under a **sibling, top-level** `crossPosts`
/// array:
///
/// ```json
/// { "message": "Message created successfully",
///   "data": { …MessageDTO fields, incl. crossPostUrls… },
///   "crossPosts": [ { "platform": "twitter", "status": "ok", "externalUrl": "…" } ] }
/// ```
///
/// Decoding a bare `MessageDTO` from that body throws `keyNotFound("id")` (the
/// id sits under `data`), so a successful publish surfaced to the user as a
/// failure — and re-tries duplicated the post (and its cross-post). This
/// decoder tolerates **both** shapes:
///  - **wrapped** — unwrap `data` and fold the top-level `crossPosts` in, and
///  - **flat** — `{ …MessageDTO… }` (the older shape; still used by the GET
///    single-message endpoint, stubs, and fixtures),
/// always yielding a single `MessageDTO` via `message`.
public struct MessageWriteResponse: Decodable, Sendable, Equatable {
    public let message: MessageDTO

    public init(message: MessageDTO) {
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case crossPosts
    }

    public init(from decoder: Decoder) throws {
        // A wrapped body has a `data` object; a flat body does not (MessageDTO
        // has no `data` field). `decodeIfPresent` returns nil for the flat case,
        // routing us to the flat fallback below.
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let wrapped = try container.decodeIfPresent(MessageDTO.self, forKey: .data) {
            let crossPosts = try container.decodeIfPresent(
                [CrossPostResultDTO].self, forKey: .crossPosts
            )
            self.message = wrapped.mergingCrossPosts(crossPosts)
        } else {
            // Flat shape — decode the message straight off the top level.
            self.message = try MessageDTO(from: decoder)
        }
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
/// One platform's row in a `POST /api/messages/[id]/reply-counts` refresh
/// (work-consolidation.md G27).
///
/// VERIFIED live 2026-09-06: a real refresh returned
/// `{"platform":"mastodon","count":0,"status":"success","checkedAt":"…"}` for
/// the connected platforms and `{"platform":"twitter","status":"unsupported",
/// "checkedAt":"…"}` for X — so `count` is **absent** when the platform cannot
/// be polled, and `status` is the field that says whether the number is real.
public struct MessageReplyCountDTO: Codable, Sendable, Equatable {
    public let platform: String
    /// Absent when `status` is not `"success"` — an unsupported platform
    /// reports no number at all rather than a misleading zero.
    public let count: Int?
    /// `"success"` / `"unsupported"` observed live; treated as an open set.
    public let status: String?
    public let checkedAt: Date?

    public init(platform: String, count: Int? = nil, status: String? = nil, checkedAt: Date? = nil) {
        self.platform = platform
        self.count = count
        self.status = status
        self.checkedAt = checkedAt
    }
}

/// `POST /api/messages/[id]/reply-counts` response — the refreshed per-platform
/// cross-post reply tallies plus the time the sweep ran.
public struct MessageReplyCountsResponse: Codable, Sendable, Equatable {
    public let replyCounts: [MessageReplyCountDTO]
    public let repliesCheckedAt: Date?

    public init(replyCounts: [MessageReplyCountDTO], repliesCheckedAt: Date? = nil) {
        self.replyCounts = replyCounts
        self.repliesCheckedAt = repliesCheckedAt
    }
}

/// `PATCH /api/messages/[id]` body — the **only** field the live route honours.
///
/// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V1). `PATCH` on a
/// message is a **reschedule** route, not a general edit route:
///   • it applies only to a scheduled post whose `scheduledAt` is still in the
///     future — on a already-published message it returns
///     `400 {"error":"Can only edit scheduled posts that are in the future"}`;
///   • `scheduledAt` is the only accepted key. A body of `content`, `title`,
///     `body`, `tags`, `publiclyVisible` or `visibility` — alone or in any
///     combination — returns `400 {"error":"No valid updates provided"}`;
///   • sending `content` *alongside* `scheduledAt` succeeds but the content is
///     **silently discarded** (confirmed: the stored `content` was unchanged
///     while `scheduledAt` moved), which is why this type deliberately cannot
///     express a content edit.
/// The reply is a **bare `MessageDTO`**, not the `MessageWriteResponse`
/// envelope that `POST /api/messages` returns.
public struct RescheduleMessageRequest: Encodable, Sendable, Equatable {
    /// The new send time. Must be in the future.
    public let scheduledAt: Date

    public init(scheduledAt: Date) {
        self.scheduledAt = scheduledAt
    }
}

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
    /// Cross-post fan-out to X/Twitter (G7).
    ///
    /// VERIFIED live 2026-08-17: sending `crossPostToTwitter: true` on
    /// `POST /api/messages` published a real post to the linked X account and the
    /// response reported it under `crossPosts` as
    /// `{ "platform": "twitter", "status": "ok", "externalUrl": "https://twitter.com/…/status/…" }`.
    /// So the request field is `crossPostToTwitter` (not `crossPostToX`) and the
    /// stable per-platform result value is `"twitter"`. The OAuth provider slug is
    /// likewise `twitter` (`GET /api/auth/twitter/status`).
    public let crossPostToTwitter: Bool?

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
        crossPostToLinkedIn: Bool? = nil,
        crossPostToTwitter: Bool? = nil
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
        self.crossPostToTwitter = crossPostToTwitter
    }

    private enum CodingKeys: String, CodingKey {
        case content, publiclyVisible, tags, parentId, pushedMessageId
        case imageUrls, videoUrls, scheduledAt
        case mastodonProviderIds, crossPostToBluesky, crossPostToLinkedIn
        case crossPostToTwitter
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
        try container.encodeIfPresent(crossPostToTwitter, forKey: .crossPostToTwitter)
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
