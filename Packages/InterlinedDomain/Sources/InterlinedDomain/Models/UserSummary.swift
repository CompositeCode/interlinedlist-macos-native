import Foundation

/// The compact author identity embedded in a message and shown on a card or
/// in a thread (PLAN.md §3 — domain models, never DTOs, reach the UI).
///
/// Maps from `UserSummaryDTO`. The DTO's `avatar` string is parsed into a
/// `URL?` here so the view layer never has to deal with a raw, possibly
/// malformed string.
public struct UserSummary: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let username: String
    /// Falls back to `username` when the DTO omits a display name, so the UI
    /// always has something to show.
    public let displayName: String
    public let avatarURL: URL?

    public init(id: String, username: String, displayName: String, avatarURL: URL? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

// MARK: - UserSearchResult (NW-1)

/// A user returned by the search / lookup surface (NW-1). Distinct from
/// `UserSummary` (the embedded message-author type) — this carries the privacy
/// flag the watcher invite and org member-add UIs need.
public struct UserSearchResult: Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatarURL: URL?
    public let isPrivate: Bool

    public init(
        id: String,
        username: String,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isPrivate = isPrivate
    }
}
