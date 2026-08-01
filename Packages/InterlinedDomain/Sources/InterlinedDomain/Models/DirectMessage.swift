import Foundation

// MARK: - DMFolder

/// The three per-user DM folders (the-gaps.md G1). Each side of a conversation
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
