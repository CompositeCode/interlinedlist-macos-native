import Foundation
import SwiftData

/// SwiftData record for a cached `Message` (PLAN.md §5 — timeline cache for
/// stale-while-revalidate). Fields mirror the round-trip surface of
/// `InterlinedDomain.Message` minus the recursively-nested repost target,
/// which is carried by `pushedMessageID` and re-hydrated by looking up the
/// referenced record at read time.
///
/// The author identity (`UserSummary`) is stored denormalized on the record so
/// the timeline can render on first paint without a join — matches the goal in
/// the M1 task brief.
///
/// Internal to the package: `MessageStore` consumers see only `Message`
/// values across the actor boundary.
@Model
final class MessageRecord {
    /// Primary key — message id from the API. SwiftData lacks declarative
    /// uniqueness in v1, so the store enforces upsert semantics by
    /// fetching-then-mutating before inserting (`mergeUpsert`).
    @Attribute(.unique) var id: String

    // Denormalized author identity — every field UserSummary needs.
    var authorID: String
    var authorUsername: String
    var authorDisplayName: String
    /// Stored as a string because SwiftData on macOS 14 handles URL
    /// optionals awkwardly under strict concurrency; mapped back to `URL?`
    /// on read.
    var authorAvatarURLString: String?

    var text: String
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]
    /// Wire-shaped boolean (matches `MessageDTO.publiclyVisible`); mapped to
    /// `Visibility` at the boundary.
    var publiclyVisible: Bool

    var digCount: Int
    var didDig: Bool
    var repostCount: Int
    /// Optional — the timeline endpoint omits it; the replies endpoint
    /// supplies it. Distinguishing "no replies" (0) from "unknown" (nil)
    /// matters to the UI, so we round-trip the optional.
    var replyCount: Int?

    var parentID: String?
    /// The id of the original message this one reposts ("pushes"). The
    /// store re-hydrates `Repost.message(...)` by looking up the referenced
    /// record on read — best-effort, dropped silently if not in cache.
    var pushedMessageID: String?

    var scheduledAt: Date?

    init(
        id: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorAvatarURLString: String?,
        text: String,
        createdAt: Date,
        updatedAt: Date,
        tags: [String],
        publiclyVisible: Bool,
        digCount: Int,
        didDig: Bool,
        repostCount: Int,
        replyCount: Int?,
        parentID: String?,
        pushedMessageID: String?,
        scheduledAt: Date?
    ) {
        self.id = id
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorAvatarURLString = authorAvatarURLString
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.publiclyVisible = publiclyVisible
        self.digCount = digCount
        self.didDig = didDig
        self.repostCount = repostCount
        self.replyCount = replyCount
        self.parentID = parentID
        self.pushedMessageID = pushedMessageID
        self.scheduledAt = scheduledAt
    }
}
