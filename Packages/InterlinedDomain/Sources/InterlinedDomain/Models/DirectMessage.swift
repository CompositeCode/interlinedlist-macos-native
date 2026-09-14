import Foundation

// MARK: - DMFolder

/// The three per-user DM folders (work-consolidation.md G1). Each side of a conversation
/// maintains its own folder membership independently.
public enum DMFolder: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case inbox
    case sent
    case deleted

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .deleted: return "Deleted"
        }
    }
}

// MARK: - DirectMessage

/// A private 1:1 message between two mutual followers.
public struct DirectMessage: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let senderId: String
    public let recipientId: String
    public let body: String
    public let imageURLs: [URL]
    public let createdAt: Date
    public let readAt: Date?
    public let sender: UserSummary?
    public let recipient: UserSummary?

    public init(
        id: String,
        senderId: String,
        recipientId: String,
        body: String,
        imageURLs: [URL] = [],
        createdAt: Date,
        readAt: Date? = nil,
        sender: UserSummary? = nil,
        recipient: UserSummary? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.recipientId = recipientId
        self.body = body
        self.imageURLs = imageURLs
        self.createdAt = createdAt
        self.readAt = readAt
        self.sender = sender
        self.recipient = recipient
    }

    /// Whether the recipient has read this message.
    public var isRead: Bool { readAt != nil }

    /// `true` when `userId` is the sender (used to align bubbles left/right).
    public func isOutgoing(currentUserId userId: String) -> Bool {
        senderId == userId
    }
}

// MARK: - DMPage

/// A cursor-paginated folder listing.
public struct DMPage: Sendable, Equatable {
    public let messages: [DirectMessage]
    public let nextCursor: String?

    public init(messages: [DirectMessage], nextCursor: String? = nil) {
        self.messages = messages
        self.nextCursor = nextCursor
    }

    public static let empty = DMPage(messages: [], nextCursor: nil)
}

// MARK: - DMThread

/// A resolved conversation with one other user.
public struct DMThread: Sendable, Equatable {
    public let messages: [DirectMessage]
    public let otherUser: UserSummary?
    public let isMutual: Bool
    public let isBlocked: Bool
    public let olderCursor: String?

    public init(
        messages: [DirectMessage],
        otherUser: UserSummary? = nil,
        isMutual: Bool = false,
        isBlocked: Bool = false,
        olderCursor: String? = nil
    ) {
        self.messages = messages
        self.otherUser = otherUser
        self.isMutual = isMutual
        self.isBlocked = isBlocked
        self.olderCursor = olderCursor
    }
}

// MARK: - DMLimits

/// The documented Direct Message ceilings (work-consolidation.md G22).
///
/// These are **not** in `GET /api/limits` — that endpoint reports the *public
/// post* limits (`message.maxContentLength` was 5000 live on 2026-09-09),
/// which is a different surface. The DM numbers come from
/// `https://interlinedlist.com/help/direct-messages`:
///
///   "You can attach photos to a direct message, up to 8 per message."
///   "you can use Markdown for formatting, up to 10,000 characters"
///
/// The per-image *size* ceilings are separate and DO come from the server —
/// they run through `ContentLimits.imagePrepLimits`, shared with the post
/// composer, so nothing here duplicates a server-driven value.
public enum DMLimits {
    /// Maximum photos attachable to one direct message.
    public static let maxImagesPerMessage = 8
    /// Maximum body length in characters. Markdown is counted raw.
    public static let maxBodyCharacters = 10_000
}

// MARK: - DMConversationSummary

/// One server-grouped conversation row from `GET /api/dm/conversations`
/// (work-consolidation.md G22).
///
/// This is the domain projection of the *real* inbox. It replaces collapsing a
/// folder page client-side, which could only ever see the conversations whose
/// newest message happened to land on the fetched page.
///
/// `latestMessage` is optional because the populated server shape is
/// unverified (the shared test account's inbox is empty and we may not write to
/// it) — a row whose message we could not decode still renders as a
/// conversation rather than vanishing or crashing.
public struct DMConversationSummary: Sendable, Equatable, Hashable, Identifiable {
    /// Stable row identity: the `pairKey` when the server sends one, else the
    /// other participant's id, else the newest message's id. Never empty.
    public let id: String
    /// The server's grouping key, when reported.
    public let pairKey: String?
    /// The other participant in the conversation.
    public let otherUser: UserSummary?
    /// Unread inbound messages in this conversation (0 when unreported).
    public let unreadCount: Int
    /// The newest message, rendered as the row preview.
    public let latestMessage: DirectMessage?

    public init(
        id: String,
        pairKey: String? = nil,
        otherUser: UserSummary? = nil,
        unreadCount: Int = 0,
        latestMessage: DirectMessage? = nil
    ) {
        self.id = id
        self.pairKey = pairKey
        self.otherUser = otherUser
        self.unreadCount = unreadCount
        self.latestMessage = latestMessage
    }

    /// The username used to open the thread. Empty only when the server named
    /// neither the other user nor a decodable message.
    public var otherUsername: String {
        otherUser?.username ?? latestMessage?.sender?.username ?? ""
    }

    /// One-line preview for the row.
    public var preview: String { latestMessage?.body ?? "" }
}

// MARK: - DMConversationPage

/// A cursor-paginated page of server-grouped conversations.
public struct DMConversationPage: Sendable, Equatable {
    public let conversations: [DMConversationSummary]
    public let nextCursor: String?

    public init(conversations: [DMConversationSummary], nextCursor: String? = nil) {
        self.conversations = conversations
        self.nextCursor = nextCursor
    }

    public static let empty = DMConversationPage(conversations: [], nextCursor: nil)
}
