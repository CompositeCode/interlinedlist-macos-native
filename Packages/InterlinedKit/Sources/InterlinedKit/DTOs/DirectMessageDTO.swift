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

// MARK: - G22: conversations inbox, single-message fetch, image upload
//
// Routes probed live 2026-09-09 (read-only — GET/OPTIONS only, no writes):
//
//   GET     /api/dm/conversations        -> 200 {"items":[],"nextCursor":null}
//   OPTIONS /api/dm/conversations        -> 204  allow: GET, HEAD, OPTIONS
//   GET     /api/dm/{id}                 -> 404 {"error":"Message not found.",
//                                                "code":"not_found"} for an
//                                           unknown id, so the route exists
//   OPTIONS /api/dm/{id}                 -> 204  allow: GET, HEAD, OPTIONS
//   OPTIONS /api/dm/images/upload        -> 204  allow: OPTIONS, POST
//   GET     /api/dm/images/upload        -> 405 (POST-only, as advertised)
//
// ⚠️ The conversations listing was **empty** on the shared test account and we
// are not permitted to send a DM to populate it, so the *populated* `items[]`
// shape is unverified. Both decoders below are therefore deliberately
// permissive rather than guessing one spelling and shipping a silent all-nil
// decode (the G21 link-metadata defect). Once a populated payload is captured,
// tighten `DMConversationDTO` to the real keys and delete the alternates.

/// One row of `GET /api/dm/conversations` — a conversation, server-grouped by
/// `pairKey`, newest first.
///
/// **Tolerant by design.** Two plausible server shapes are accepted:
///
/// 1. *Nested* — the row is a conversation envelope that carries its newest
///    message under `lastMessage` / `latestMessage` / `message`.
/// 2. *Flattened* — the row **is** the newest message per pair (the natural
///    output of a `GROUP BY pairKey`), i.e. a `DirectMessageDTO` with the
///    conversation extras alongside it.
///
/// Every field is optional, so an unexpected spelling degrades to `nil`
/// instead of failing the whole page decode.
public struct DMConversationDTO: Decodable, Sendable, Equatable {

    /// `senderId:recipientId` conversation key — the server's grouping key.
    public let pairKey: String?
    /// The other participant, when the server names them on the row.
    public let otherUser: UserSummaryDTO?
    /// Unread inbound messages in this conversation, when reported.
    public let unreadCount: Int?
    /// The newest message in the conversation, from either shape above.
    public let lastMessage: DirectMessageDTO?

    public init(
        pairKey: String? = nil,
        otherUser: UserSummaryDTO? = nil,
        unreadCount: Int? = nil,
        lastMessage: DirectMessageDTO? = nil
    ) {
        self.pairKey = pairKey
        self.otherUser = otherUser
        self.unreadCount = unreadCount
        self.lastMessage = lastMessage
    }

    /// Alternate key spellings, tried in order. The first that decodes wins.
    private enum CodingKeys: String, CodingKey {
        // pairKey
        case pairKey, conversationKey, key
        // otherUser
        case otherUser, user, participant, withUser, other
        // unreadCount
        case unreadCount, unread, unreadMessages
        // lastMessage
        case lastMessage, latestMessage, message, newestMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pairKey = Self.first(String.self, in: container, keys: [.pairKey, .conversationKey, .key])
        self.otherUser = Self.first(
            UserSummaryDTO.self,
            in: container,
            keys: [.otherUser, .user, .participant, .withUser, .other]
        )
        self.unreadCount = Self.first(Int.self, in: container, keys: [.unreadCount, .unread, .unreadMessages])
        // Shape 1: a nested newest message. Shape 2: the row *is* the message,
        // so re-decode the same container as a `DirectMessageDTO`.
        if let nested = Self.first(
            DirectMessageDTO.self,
            in: container,
            keys: [.lastMessage, .latestMessage, .message, .newestMessage]
        ) {
            self.lastMessage = nested
        } else {
            self.lastMessage = try? DirectMessageDTO(from: decoder)
        }
    }

    /// Decodes the first of `keys` that is present and well-typed, else `nil`.
    /// A key that is present but the wrong type is skipped rather than fatal —
    /// the point of this decoder is that no single guess can break the page.
    private static func first<T: Decodable>(
        _ type: T.Type,
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> T? {
        for key in keys {
            if let value = (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil {
                return value
            }
        }
        return nil
    }
}

/// `GET /api/dm/conversations` response — the same `{items, nextCursor}`
/// envelope as the folder listing, verified live 2026-09-09 (empty page).
public struct DMConversationsPage: Decodable, Sendable, Equatable {
    public let items: [DMConversationDTO]
    public let nextCursor: String?

    public init(items: [DMConversationDTO], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// `GET /api/dm/{id}` response — a single message (the deep-link target).
///
/// **Tolerant by design.** This API has documented envelope drift (`POST
/// /api/messages` wraps under `data`; `POST /api/dm` wraps under `message`),
/// and the success body could not be captured — the test account has no
/// messages and we may not create one. So three shapes are accepted: wrapped
/// under `message`, wrapped under `data`, or the bare message object.
public struct DMMessageResponse: Decodable, Sendable, Equatable {
    public let message: DirectMessageDTO

    public init(message: DirectMessageDTO) { self.message = message }

    private enum CodingKeys: String, CodingKey {
        case message, data, dm
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            for key in [CodingKeys.message, .data, .dm] {
                if let nested = (try? container.decodeIfPresent(DirectMessageDTO.self, forKey: key)) ?? nil {
                    self.message = nested
                    return
                }
            }
        }
        // Bare object — decode the payload itself as the message. This is the
        // one path that is allowed to throw, so a genuinely unreadable body
        // still surfaces as `APIError.decoding` rather than a silent nil.
        self.message = try DirectMessageDTO(from: decoder)
    }
}
