import Foundation
import InterlinedDomain

/// Internal mapping between SwiftData `MessageRecord` and the domain
/// `Message` value type. Kept package-internal so the public API surface
/// stays narrow: callers consume `Message` values across the actor boundary
/// and never see the `@Model` types directly (which is critical under Swift
/// 6 strict concurrency — `@Model` instances are not `Sendable`).

extension MessageRecord {

    /// Build a new record from a domain `Message`. The recursive repost
    /// target collapses to `pushedMessageID`; the store separately upserts
    /// the original message so a later read can re-hydrate `Repost`.
    convenience init(from message: Message) {
        self.init(
            id: message.id,
            authorID: message.author.id,
            authorUsername: message.author.username,
            authorDisplayName: message.author.displayName,
            authorAvatarURLString: message.author.avatarURL?.absoluteString,
            text: message.text,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            tags: message.tags,
            publiclyVisible: message.visibility.isPubliclyVisible,
            digCount: message.digCount,
            didDig: message.didDig,
            repostCount: message.repostCount,
            replyCount: message.replyCount,
            parentID: message.parentID,
            pushedMessageID: message.repost?.original.id,
            scheduledAt: message.scheduledAt
        )
    }

    /// Copy fresh field values from a domain `Message` into an existing
    /// managed record — the upsert path. Must touch every mutable field so
    /// stale data never leaks through.
    func apply(_ message: Message) {
        // `id` is the primary key, so it stays.
        authorID = message.author.id
        authorUsername = message.author.username
        authorDisplayName = message.author.displayName
        authorAvatarURLString = message.author.avatarURL?.absoluteString
        text = message.text
        createdAt = message.createdAt
        updatedAt = message.updatedAt
        tags = message.tags
        publiclyVisible = message.visibility.isPubliclyVisible
        digCount = message.digCount
        didDig = message.didDig
        repostCount = message.repostCount
        replyCount = message.replyCount
        parentID = message.parentID
        pushedMessageID = message.repost?.original.id
        scheduledAt = message.scheduledAt
    }

    /// Hydrate the denormalized author back into a `UserSummary`.
    var authorSummary: UserSummary {
        UserSummary(
            id: authorID,
            username: authorUsername,
            displayName: authorDisplayName,
            avatarURL: authorAvatarURLString.flatMap(URL.init(string:))
        )
    }

    /// Hydrate a domain `Message` from this record. `repostLookup` is given
    /// the `pushedMessageID` and may return the cached original; if it
    /// returns `nil`, the repost target is dropped (best-effort cache).
    func toMessage(repostLookup: (String) -> Message?) -> Message {
        let repost: Repost? = pushedMessageID.flatMap { id in
            repostLookup(id).map { .message($0) }
        }
        return Message(
            id: id,
            author: authorSummary,
            text: text,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: tags,
            visibility: Visibility(publiclyVisible: publiclyVisible),
            digCount: digCount,
            didDig: didDig,
            repostCount: repostCount,
            replyCount: replyCount,
            parentID: parentID,
            repost: repost,
            scheduledAt: scheduledAt
        )
    }
}

extension TimelineScope {
    /// Stable string form for the SwiftData composite key. Switching on the
    /// case rather than using `rawValue` keeps the enum free of a wire
    /// representation in the domain layer.
    var rawScopeKey: String {
        switch self {
        case .all:       return "all"
        case .mine:      return "mine"
        // Following has no API backing yet; a stable key is still needed so
        // any future cache entries survive enum expansion without corruption.
        case .following: return "following"
        }
    }
}
