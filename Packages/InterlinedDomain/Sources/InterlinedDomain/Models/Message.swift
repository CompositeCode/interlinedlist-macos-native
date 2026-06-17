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
        scheduledAt: Date? = nil
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
