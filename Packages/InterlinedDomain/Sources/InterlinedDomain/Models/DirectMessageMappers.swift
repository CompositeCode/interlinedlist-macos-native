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
