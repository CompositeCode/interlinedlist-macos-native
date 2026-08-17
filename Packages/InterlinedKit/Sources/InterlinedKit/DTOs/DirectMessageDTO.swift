import Foundation

// MARK: - Direct Message DTOs (work-consolidation.md G1)
//
// Shapes verified live 2026-07-31 via an authorized recon DM (sent from the
// test account, captured, then trashed):
//
//   POST /api/dm                     -> { "message": DirectMessageDTO }        (201)
//   GET  /api/dm?folder=inbox|sent|deleted&cursor=
//                                    -> { "items": [DirectMessageDTO], "nextCursor": String? }
//   GET  /api/dm/thread/{username}   -> { "items": [...], "olderCursor": String?,
//                                         "isMutual": Bool, "isBlocked": Bool,
//                                         "otherUser": UserSummaryDTO }
//   GET  /api/dm/recipients          -> { "recipients": [UserSummaryDTO] }
//   GET  /api/dm/unread-count        -> { "count": Int }
//   POST /api/dm/{id}/{read,trash,restore} -> { "ok": true }
//
// `sender` / `recipient` reuse the compact `UserSummaryDTO` shape.

/// A single direct message.
public struct DirectMessageDTO: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    /// `senderId:recipientId` conversation key.
    public let pairKey: String?
    public let senderId: String
    public let recipientId: String
    public let body: String
    public let imageUrls: [String]?
    public let createdAt: Date
    /// `nil` while unread; set to the read timestamp once the recipient opens it.
    public let readAt: Date?
    public let sender: UserSummaryDTO?
    public let recipient: UserSummaryDTO?
    /// Server-truncated preview string.
    public let preview: String?

    public init(
        id: String,
        pairKey: String? = nil,
        senderId: String,
        recipientId: String,
        body: String,
        imageUrls: [String]? = nil,
        createdAt: Date,
        readAt: Date? = nil,
        sender: UserSummaryDTO? = nil,
        recipient: UserSummaryDTO? = nil,
        preview: String? = nil
    ) {
        self.id = id
        self.pairKey = pairKey
        self.senderId = senderId
        self.recipientId = recipientId
        self.body = body
        self.imageUrls = imageUrls
        self.createdAt = createdAt
        self.readAt = readAt
        self.sender = sender
        self.recipient = recipient
        self.preview = preview
    }
}

/// `POST /api/dm` response — the created message wrapped under `message`.
public struct DMCreateResponse: Decodable, Sendable, Equatable {
    public let message: DirectMessageDTO
    public init(message: DirectMessageDTO) { self.message = message }
}

/// `GET /api/dm?folder=…` response — a cursor-paginated folder listing.
public struct DMFolderPage: Decodable, Sendable, Equatable {
    public let items: [DirectMessageDTO]
    public let nextCursor: String?
    public init(items: [DirectMessageDTO], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// `GET /api/dm/thread/{username}` (and `/updates`) response.
public struct DMThreadResponse: Decodable, Sendable, Equatable {
    public let items: [DirectMessageDTO]
    public let olderCursor: String?
    public let isMutual: Bool?
    public let isBlocked: Bool?
    public let otherUser: UserSummaryDTO?

    public init(
        items: [DirectMessageDTO],
        olderCursor: String? = nil,
        isMutual: Bool? = nil,
        isBlocked: Bool? = nil,
        otherUser: UserSummaryDTO? = nil
    ) {
        self.items = items
        self.olderCursor = olderCursor
        self.isMutual = isMutual
        self.isBlocked = isBlocked
        self.otherUser = otherUser
    }
}

/// `GET /api/dm/recipients` response — the users the caller may DM.
public struct DMRecipientsResponse: Decodable, Sendable, Equatable {
    public let recipients: [UserSummaryDTO]
    public init(recipients: [UserSummaryDTO]) { self.recipients = recipients }
}

/// `GET /api/dm/unread-count` response.
public struct DMUnreadCountResponse: Decodable, Sendable, Equatable {
    public let count: Int
    public init(count: Int) { self.count = count }
}

/// Body for `POST /api/dm`: `{ recipientId, body, imageUrls? }`.
public struct SendDirectMessageRequest: Encodable, Sendable, Equatable {
    public let recipientId: String
    public let body: String
    public let imageUrls: [String]?

    public init(recipientId: String, body: String, imageUrls: [String]? = nil) {
        self.recipientId = recipientId
        self.body = body
        self.imageUrls = imageUrls
    }
}

/// Decode-safe acknowledgement for the DM actions (`read` / `trash` / `restore`).
/// The service sends these via `sendVoid`, so the body is ignored; `ok` is
/// optional so the type decodes regardless of the exact success payload.
public struct DMActionResponse: Decodable, Sendable, Equatable {
    public let ok: Bool?
    public init(ok: Bool? = nil) { self.ok = ok }
}
