import Foundation

/// A single timeline message (post), as the UI consumes it (PLAN.md §1, §3).
///
/// This is the domain projection of `MessageDTO`: optional/nullable wire
/// fields are resolved into sensible non-optional defaults where the UI always
/// needs a value (`tags` defaults to `[]`), the `publiclyVisible` boolean
/// becomes a `Visibility`, and the recursively-nested repost target is carried
/// as an indirect `repost`. No `MessageDTO` ever escapes this package.
public struct Message: Sendable, Equatable, Identifiable {
    public let id: String
    /// The author identity for the card / thread row.
    public let author: UserSummary
    /// The message body. Markdown source is authored inline here; the renderer
    /// in the App layer turns it into attributed text.
    public let text: String
    public let createdAt: Date
    public let updatedAt: Date
    public let tags: [String]
    public let visibility: Visibility

    /// "I Dig!" reaction count and whether the signed-in user has dug it.
    public let digCount: Int
    public let didDig: Bool

    /// Repost ("push") count.
    public let repostCount: Int

    /// Number of direct replies, when the payload carries it. `nil` when the
    /// message endpoint did not include a reply count (the list endpoint does
    /// not; the replies endpoint reports its own `total`). Kept optional rather
    /// than defaulted to `0` so the UI can distinguish "no replies" from
    /// "unknown".
    public let replyCount: Int?

    /// The id of the parent message when this is a reply.
    public let parentID: String?

    /// The original message this post reposted, if any. `indirect` because a
    /// `Message` can contain another `Message`.
    public let repost: Repost?

    /// When set, the message is scheduled for future publication at this time.
    public let scheduledAt: Date?

    /// Per-platform cross-post outcomes attached to a published message.
    /// Empty when the message was not cross-posted or when the server did not
    /// return cross-post data for this response.
    public let crossPostResults: [CrossPostResult]

    /// Server-rendered rich link previews for URLs found in the body
    /// (feature-gaps §1.5). Empty when the message contains no links or the
    /// server did not resolve any preview metadata for this response.
    ///
    /// SCOPE DECISION (feature-gaps §1.5): link previews are treated as a
    /// fetch-time / UI concern and are **not** persisted in SwiftData
    /// (`MessageRecord`). They are re-derived from the DTO on every load,
    /// refreshing naturally on the next fetch. This deliberately avoids a
    /// SwiftData schema migration; the trade-off is that previews are absent
    /// when a row is rendered purely from the local cache before a refresh.
    public let linkPreviews: [LinkPreview]

    public init(
        id: String,
        author: UserSummary,
        text: String,
        createdAt: Date,
        updatedAt: Date,
        tags: [String] = [],
        visibility: Visibility,
        digCount: Int,
        didDig: Bool,
        repostCount: Int,
        replyCount: Int? = nil,
        parentID: String? = nil,
        repost: Repost? = nil,
        scheduledAt: Date? = nil,
        crossPostResults: [CrossPostResult] = [],
        linkPreviews: [LinkPreview] = []
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.visibility = visibility
        self.digCount = digCount
        self.didDig = didDig
        self.repostCount = repostCount
        self.replyCount = replyCount
        self.parentID = parentID
        self.repost = repost
        self.scheduledAt = scheduledAt
        self.crossPostResults = crossPostResults
        self.linkPreviews = linkPreviews
    }
}

/// Indirection box for a reposted message. A value type cannot contain itself
/// by value, so the nested original message is held behind `indirect`.
public indirect enum Repost: Sendable, Equatable {
    case message(Message)

    /// The reposted original.
    public var original: Message {
        switch self {
        case .message(let message): return message
        }
    }
}

// MARK: - CrossPostResult (NW-2)

/// The per-platform cross-post outcome attached to a published message.
/// Maps from `CrossPostResultDTO`; the wire status string is narrowed to a
/// typed enum with a forward-compatible `.unknown` case.
public struct CrossPostResult: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case ok
        case failed(String?)
        case pending
        case unknown(String)
    }

    public let platform: String
    public let providerId: String?
    public let status: Status
    public let externalURL: URL?

    public init(
        platform: String,
        providerId: String? = nil,
        status: Status,
        externalURL: URL? = nil
    ) {
        self.platform = platform
        self.providerId = providerId
        self.status = status
        self.externalURL = externalURL
    }
}

// MARK: - LinkPreview (feature-gaps §1.5)

/// A server-rendered rich link preview attached to a message.
///
/// Maps from `LinkPreviewDTO`. The wire `url` string is coerced to a `URL`
/// during mapping and entries whose `url` will not parse are dropped, so a
/// `LinkPreview` always carries a usable `url`. The remaining fields mirror the
/// server's Open Graph resolution and stay optional because the server may not
/// have finished (or succeeded at) fetching them.
public struct LinkPreview: Sendable, Equatable, Identifiable {
    /// The resolved link. Doubles as the stable identity for `ForEach`.
    public let url: URL
    /// Source platform label the server attached (e.g. "youtube", "github"),
    /// when it recognised one.
    public let platform: String?
    /// The server's fetch-state string for this preview. The exact vocabulary
    /// (which value means "ready") is **not documented** in the API reference
    /// as of 2026-07-18 — see `isFetchStatusReady`. Kept as the raw string so
    /// no information is lost and the client stays forward-compatible.
    public let fetchStatus: String?
    public let title: String?
    public let description: String?
    public let imageURL: URL?

    public var id: URL { url }

    public init(
        url: URL,
        platform: String? = nil,
        fetchStatus: String? = nil,
        title: String? = nil,
        description: String? = nil,
        imageURL: URL? = nil
    ) {
        self.url = url
        self.platform = platform
        self.fetchStatus = fetchStatus
        self.title = title
        self.description = description
        self.imageURL = imageURL
    }

    /// Whether `fetchStatus` names a state the client recognises as a completed,
    /// successful fetch.
    ///
    /// NOTE (backend question, feature-gaps §1.5): the API reference does not
    /// document the `fetchStatus` vocabulary, so we cannot be certain which
    /// string means "ready". This matches a small, case-insensitive set of the
    /// conventional success tokens. It is intentionally **not** the sole gate on
    /// rendering — `isRenderable` also renders whenever a title or image is
    /// present — so an unknown-but-successful status string never hides an
    /// otherwise-complete card.
    public var isFetchStatusReady: Bool {
        guard let status = fetchStatus?.lowercased() else { return false }
        return ["ready", "success", "succeeded", "ok", "complete", "completed", "fetched"].contains(status)
    }

    /// Whether this preview carries enough resolved metadata to be worth
    /// rendering as a card. True when the server reports a ready fetch status
    /// OR when a human-meaningful field (title or image) is present. A bare URL
    /// with no resolved metadata returns `false` — the UI degrades to nothing
    /// (or a minimal chip) rather than an empty card.
    public var isRenderable: Bool {
        if isFetchStatusReady { return true }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if imageURL != nil { return true }
        return false
    }

    /// The host component shown as the card subtitle (e.g. "github.com"),
    /// stripped of a leading `www.`. Falls back to the full URL string when the
    /// URL has no host.
    public var displayHost: String {
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// One page of a timeline read: the messages plus the cursor needed to ask for
/// the next page. Maps the kit's `PaginationInfo` envelope into the two values
/// the UI's infinite scroll actually needs.
public struct TimelinePage: Sendable, Equatable {
    public let messages: [Message]
    /// Whether the server reports more messages beyond this page.
    public let hasMore: Bool
    /// The `offset` to pass for the next page. `nil` when `hasMore` is false.
    public let nextOffset: Int?

    public init(messages: [Message], hasMore: Bool, nextOffset: Int?) {
        self.messages = messages
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// An empty page with no further results — the boundary value used when a
    /// scope has no messages.
    public static let empty = TimelinePage(messages: [], hasMore: false, nextOffset: nil)
}
