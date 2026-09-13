import Foundation

/// Which slice of the feed the account's stored "Viewing" preference asks for
/// (work-consolidation.md G35 / issue #43).
///
/// This is the domain projection of `UserDTO.viewingPreference`, which was
/// decoded but deliberately excluded from `UserSettings` because the valid value
/// set was unconfirmed. It is confirmed now.
///
/// **Wire vocabulary — VERIFIED live 2026-09-09.** The web Settings form's own
/// `<select id="viewingPreference">` offers exactly four `<option value>` tokens,
/// and the test account reads back `"all_messages"`:
///
/// | Token             | Label           |
/// |-------------------|-----------------|
/// | `my_messages`     | My Messages     |
/// | `all_messages`    | All Messages    |
/// | `followers_only`  | Followers Only  |
/// | `following_only`  | Following Only  |
///
/// `other` is a deliberate escape hatch, not dead code: it preserves a token the
/// server introduces later so a macOS save round-trips it untouched instead of
/// silently rewriting the account to `all_messages`. Nothing throws on an
/// unrecognised token — `defaultScope` resolves it to `.all`, the safest feed.
public enum ViewingPreference: Sendable, Equatable, Hashable {

    /// Only the signed-in account's own messages.
    case myMessages
    /// Everyone's public timeline. The server default.
    case allMessages
    /// Messages from accounts that follow you. **No backend feed exists** —
    /// see `hasBackendFeed`.
    case followersOnly
    /// Messages from accounts you follow. **No backend feed exists** — this is
    /// the same P1-G gap that keeps `TimelineScope.following` short-circuited.
    case followingOnly
    /// A token this build does not recognise, carried verbatim so a save never
    /// clobbers a value set by a newer server or by the web.
    case other(String)

    /// Maps a wire token onto a case. Unknown, empty, and whitespace-only
    /// tokens become `.other`; `nil` is the caller's problem (use
    /// `init(wireToken:)` with the server default when the field is absent).
    public init(wireToken: String) {
        switch wireToken.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "my_messages":    self = .myMessages
        case "all_messages":   self = .allMessages
        case "followers_only": self = .followersOnly
        case "following_only": self = .followingOnly
        case let token:        self = .other(token)
        }
    }

    /// The token sent back in `UpdateUserRequest.viewingPreference`.
    public var wireToken: String {
        switch self {
        case .myMessages:       return "my_messages"
        case .allMessages:      return "all_messages"
        case .followersOnly:    return "followers_only"
        case .followingOnly:    return "following_only"
        case .other(let token): return token
        }
    }

    /// Human label, matching the web form's `<option>` text exactly so the two
    /// clients read the same.
    public var displayName: String {
        switch self {
        case .myMessages:       return "My Messages"
        case .allMessages:      return "All Messages"
        case .followersOnly:    return "Followers Only"
        case .followingOnly:    return "Following Only"
        case .other(let token): return token
        }
    }

    /// The four values a user can pick, in the web form's order. `.other` is
    /// never offered — it only ever arrives from the server.
    public static let selectable: [ViewingPreference] = [
        .myMessages, .allMessages, .followersOnly, .followingOnly
    ]

    /// The timeline scope this preference asks the feed to open on.
    ///
    /// An unrecognised token resolves to `.all` rather than throwing: the
    /// account still gets a working feed, and the stored token is preserved for
    /// round-trip by `wireToken`.
    public var defaultScope: TimelineScope {
        switch self {
        case .myMessages:    return .mine
        case .allMessages:   return .all
        case .followersOnly: return .followers
        case .followingOnly: return .following
        case .other:         return .all
        }
    }

    /// Whether the API can actually serve this slice today.
    ///
    /// VERIFIED live 2026-09-09: `GET /api/messages` honours only `onlyMine`.
    /// `?scope=following`, `?viewingPreference=followers_only` and
    /// `?filter=followers_only` all return the identical unfiltered page, so
    /// neither follower feed exists (P1-G). The UI must show the honest
    /// "coming soon" empty state for these rather than a silently-wrong feed.
    public var hasBackendFeed: Bool {
        switch self {
        case .myMessages, .allMessages, .other: return true
        case .followersOnly, .followingOnly:    return false
        }
    }
}
