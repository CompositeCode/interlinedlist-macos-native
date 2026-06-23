import Foundation

/// Role granted to a watcher on a shared list (PLAN.md §1 "List sharing", §6
/// M3).
///
/// **Assumption (not yet documented upstream).** The role taxonomy for
/// `PUT /api/lists/[id]/watchers/[userId]` is not enumerated in the API docs
/// — `/API-backend-prompts-to-build.md` item 1.2 records this gap and proposes
/// `owner | editor | viewer` as the working set. The M3 share-sheet picker
/// renders against that set; if the upstream taxonomy lands with a different
/// shape, this enum is the one place to update.
///
/// `other(String)` preserves any unrecognised wire string so an unexpected
/// role round-trips through the UI rather than crashing a switch.
public enum WatcherRole: Sendable, Equatable, Hashable {

    /// Full control. By the working assumption: read, edit rows, edit schema,
    /// manage watchers, delete the list.
    case owner

    /// Edit access. By the working assumption: read and edit rows; cannot
    /// edit schema, manage watchers, or delete the list.
    case editor

    /// Read-only access. By the working assumption: read rows.
    case viewer

    /// A role token the client does not yet recognise. Treated as no-edit /
    /// no-share for safety; preserved for display.
    case other(String)

    /// The canonical wire token for this role. The wire taxonomy is the
    /// open question above — this aligns with the prompts-file proposal.
    public var wireToken: String {
        switch self {
        case .owner: return "owner"
        case .editor: return "editor"
        case .viewer: return "viewer"
        case .other(let raw): return raw
        }
    }

    /// Maps a wire string to a role, case-insensitively. Unknown tokens
    /// preserve their original casing under `.other`.
    public init(wireToken: String) {
        switch wireToken.lowercased() {
        case "owner": self = .owner
        case "editor", "collaborator", "manager": self = .editor
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

    /// The watching user's username when the API includes it on this row
    /// (`/watchers/users` returns it; the per-list `/watchers` may omit it).
    public let username: String?

    /// The watcher's role on this list. See `WatcherRole` for the taxonomy
    /// assumption.
    public let role: WatcherRole

    /// When the watcher was added, when the API includes the timestamp.
    public let createdAt: Date?

    public var id: String { userId }

    public init(
        userId: String,
        username: String? = nil,
        role: WatcherRole,
        createdAt: Date? = nil
    ) {
        self.userId = userId
        self.username = username
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
