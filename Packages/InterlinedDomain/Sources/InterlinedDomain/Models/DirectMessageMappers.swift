import Foundation
import InterlinedKit

// MARK: - Direct Message DTO → domain mapping
//
// Per-group slice of the audit-in-one-place mapper convention (PLAN.md §3).
// Per decision 0003 the App layer never references the kit DTOs — the DM
// service returns `DirectMessage` / `DMPage` / `DMThread`, and this file is the
// one place those cross the boundary. `sender` / `recipient` reuse the existing
// `UserSummary.init(from: UserSummaryDTO)` mapper.

extension DirectMessage {
    public init(from dto: DirectMessageDTO) {
        self.init(
            id: dto.id,
            senderId: dto.senderId,
            recipientId: dto.recipientId,
            body: dto.body,
            imageURLs: (dto.imageUrls ?? []).compactMap(URL.init(string:)),
            createdAt: dto.createdAt,
            readAt: dto.readAt,
            sender: dto.sender.map(UserSummary.init(from:)),
            recipient: dto.recipient.map(UserSummary.init(from:))
        )
    }
}

extension DMPage {
    public init(from dto: DMFolderPage) {
        self.init(
            messages: dto.items.map(DirectMessage.init(from:)),
            nextCursor: dto.nextCursor
        )
    }
}

extension DMThread {
    public init(from dto: DMThreadResponse) {
        self.init(
            messages: dto.items.map(DirectMessage.init(from:)),
            otherUser: dto.otherUser.map(UserSummary.init(from:)),
            isMutual: dto.isMutual ?? false,
            isBlocked: dto.isBlocked ?? false,
            olderCursor: dto.olderCursor
        )
    }
}

// MARK: - G22: server-grouped conversations

extension DMConversationSummary {

    /// Maps one `GET /api/dm/conversations` row.
    ///
    /// Identity falls through `pairKey` → other participant's id → newest
    /// message id → `fallbackID`, so a row is never dropped, nor collides with
    /// a sibling row, for want of an id — which matters because the populated
    /// server shape is unverified and the decoder is deliberately permissive.
    ///
    /// `unreadCount` defaults to 0 rather than nil: an unreported count means
    /// "nothing to badge", and a phantom badge is worse than a missing one.
    ///
    /// - Parameter fallbackID: last-resort identity, supplied by the page
    ///   mapper as the row's position so it is unique within the page.
    public init(from dto: DMConversationDTO, fallbackID: String) {
        let message = dto.lastMessage.map(DirectMessage.init(from:))
        let other = dto.otherUser.map(UserSummary.init(from:))
        let identity = [dto.pairKey, other?.id, message?.id]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? fallbackID
        self.init(
            id: identity,
            pairKey: dto.pairKey,
            otherUser: other,
            unreadCount: dto.unreadCount ?? 0,
            latestMessage: message
        )
    }
}

extension DMConversationPage {
    public init(from dto: DMConversationsPage) {
        self.init(
            conversations: dto.items.enumerated().map { index, item in
                DMConversationSummary(from: item, fallbackID: "dm-conversation-\(index)")
            },
            nextCursor: dto.nextCursor
        )
    }
}
