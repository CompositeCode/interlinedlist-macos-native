import Foundation

/// Role granted to a watcher on a shared list (PLAN.md §1 "List sharing", §6
/// M3).
///
/// **The taxonomy is now documented.** `/help/api/lists` states: "A watcher's
/// role is one of `watcher`, `collaborator`, or `manager`", and an invalid or
/// missing `role` on `PUT /api/lists/:id/watchers/:userId` is a `400`. The
/// three cases below are the client-side names for exactly those three roles;
/// `wireToken` emits the documented strings.
///
/// - Warning: before work-consolidation.md G23 this enum emitted
///   `owner` / `editor` / `viewer` as wire tokens — none of which the API
///   accepts — so every role change was rejected with a `400`. The case names
///   are kept (the pickers and `.other` fallback depend on them); only the
///   wire mapping and the UI labels moved onto the documented vocabulary.
///
/// `other(String)` preserves any unrecognised wire string so an unexpected
/// role round-trips through the UI rather than crashing a switch.
public enum WatcherRole: Sendable, Equatable, Hashable, CaseIterable {

    /// Full control — the API's `manager`. Read, edit rows, edit schema,
    /// manage watchers, delete the list. The web labels this **Admin**.
    case owner

    /// Edit access — the API's `collaborator`. Read and edit rows. The web
    /// labels this **Edit**.
    case editor

    /// Read-only access — the API's `watcher`. The web labels this
    /// **Read-only**.
    case viewer

    /// A role token the client does not yet recognise. Treated as no-edit /
    /// no-share for safety; preserved for display.
    case other(String)

    /// The three roles a picker offers. `.other` is a decode-tolerance case,
    /// never something the user can choose, so it is excluded.
    public static var allCases: [WatcherRole] { [.viewer, .editor, .owner] }

    /// The canonical wire token, per `/help/api/lists`.
    public var wireToken: String {
        switch self {
        case .owner: return "manager"
        case .editor: return "collaborator"
        case .viewer: return "watcher"
        case .other(let raw): return raw
        }
    }

    /// UI-facing label, matching the web's vocabulary on `/help/lists`
    /// (Read-only → `watcher`, Edit → `collaborator`, Admin → `manager`).
    public var label: String {
        switch self {
        case .owner: return "Admin"
        case .editor: return "Edit"
        case .viewer: return "Read-only"
        case .other(let raw): return raw.capitalized
        }
    }

    /// Maps a wire string to a role, case-insensitively. Unknown tokens
    /// preserve their original casing under `.other`.
    public init(wireToken: String) {
        switch wireToken.lowercased() {
        case "owner", "manager": self = .owner
        case "editor", "collaborator": self = .editor
        case "viewer", "watcher", "reader": self = .viewer
        default: self = .other(wireToken)
        }
    }
}

/// A watcher entry on a shared list — the public projection of the
/// `ListWatcherDTO` returned by the watcher endpoints.
public struct ListWatcher: Sendable, Equatable, Hashable, Identifiable {

    /// The watching user's id. Identity for `Identifiable`.
    public let userId: String

    /// The watching user's username, read from the row's nested `user` object
    /// (with the older flat `username` field as a fallback).
    public let username: String?

    /// The watching user's display name, when the nested `user` carries one.
    public let displayName: String?

    /// The watching user's avatar, when the nested `user` carries one.
    public let avatarURL: URL?

    /// The watcher's role on this list. See `WatcherRole`.
    public let role: WatcherRole

    /// When the watcher was added, when the API includes the timestamp.
    public let createdAt: Date?

    public var id: String { userId }

    /// Best available human label: display name, then username, then a neutral
    /// fallback so a row never renders blank.
    public var displayLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return "User"
    }

    public init(
        userId: String,
        username: String? = nil,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        role: WatcherRole,
        createdAt: Date? = nil
    ) {
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.role = role
        self.createdAt = createdAt
    }
}

/// The caller's own watcher status on a list (response of
/// `GET /api/lists/[id]/watchers/me`). The role is `nil` when the caller is
/// not watching at all (`isWatching == false`).
public struct WatcherStatus: Sendable, Equatable, Hashable {

    /// Whether the caller currently watches this list.
    public let isWatching: Bool

    /// The caller's role when `isWatching == true`; `nil` otherwise.
    public let role: WatcherRole?

    public init(isWatching: Bool, role: WatcherRole?) {
        self.isWatching = isWatching
        self.role = role
    }
}
