import Foundation
import InterlinedKit

// MARK: - DTO → domain mapping
//
// One file owns every kit-DTO → domain-model translation so the boundary is
// auditable in a single place (PLAN.md §3 "DTOs never cross into the UI;
// domain models do"). Mappers are pure, total functions implemented as
// `init(from:)` so call sites read as plain conversions.

extension UserSummary {
    /// Maps the embedded author summary. Display name falls back to the
    /// username when the API omits it; the avatar string is parsed into a URL
    /// and silently dropped if it is not a valid URL.
    public init(from dto: UserSummaryDTO) {
        self.init(
            id: dto.id,
            username: dto.username,
            displayName: dto.displayName ?? dto.username,
            avatarURL: dto.avatar.flatMap(URL.init(string:))
        )
    }
}

extension CurrentUser {
    /// Maps the full account from the `GET /api/user` payload (the nested
    /// `UserDTO`). `customerStatus` is narrowed to the typed `CustomerStatus`;
    /// nullable account flags collapse to `false` defaults.
    public init(from dto: UserDTO) {
        self.init(
            summary: UserSummary(
                id: dto.id,
                username: dto.username,
                displayName: dto.displayName ?? dto.username,
                avatarURL: dto.avatar.flatMap(URL.init(string:))
            ),
            email: dto.email,
            customerStatus: CustomerStatus(raw: dto.customerStatus),
            isEmailVerified: dto.emailVerified,
            isPrivateAccount: dto.isPrivateAccount ?? false,
            createdAt: dto.createdAt
        )
    }
}

extension Message {
    /// Maps a message. Nullable `tags` collapses to `[]`; `publiclyVisible`
    /// becomes a `Visibility`; the nested repost target (when present) is
    /// mapped recursively. `replyCount` is left `nil` because `MessageDTO`
    /// carries no reply count — the replies endpoint reports its own total.
    public init(from dto: MessageDTO) {
        self.init(
            id: dto.id,
            author: UserSummary(from: dto.user),
            text: dto.content,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            tags: dto.tags ?? [],
            visibility: Visibility(publiclyVisible: dto.publiclyVisible),
            digCount: dto.digCount,
            didDig: dto.dugByMe,
            repostCount: dto.pushCount,
            replyCount: nil,
            parentID: dto.parentId,
            repost: dto.pushedMessage.map { box in
                Repost.message(Message(from: box.message))
            },
            scheduledAt: dto.scheduledAt
        )
    }
}

extension TimelinePage {
    /// Builds a page from the kit's `Paginated<MessageDTO>` envelope, mapping
    /// each DTO and deriving the next-page cursor from the pagination block.
    public init(from paginated: Paginated<MessageDTO>) {
        let messages = paginated.items.map(Message.init(from:))
        let info = paginated.pagination
        self.init(
            messages: messages,
            hasMore: info.hasMore,
            nextOffset: info.hasMore ? info.offset + info.limit : nil
        )
    }
}
