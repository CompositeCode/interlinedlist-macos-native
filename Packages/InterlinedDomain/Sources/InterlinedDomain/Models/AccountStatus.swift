import Foundation

/// A typed reading of the API's `accountStatus` string (GitHub #42).
///
/// Every InterlinedList account carries a status that decides what it may do,
/// **independently of subscription tier and of email verification**. It arrives
/// on `GET /api/user` (verified live 2026-09-09: `"accountStatus":"active"`).
///
/// The wire field is an open `String` — `GET /api/openapi.json` declares the
/// `User.accountStatus` property as a bare `{"type":"string"}` with **no enum**,
/// so the server is free to introduce values this client has never seen. The
/// closed set below is documented at `/help/account`, not by the schema:
///
/// | case | what it means |
/// |---|---|
/// | `.new` | On probation. Read/browse/follow/block/mute/report work. Plain posting is *rate-limited*, not blocked. DMs, media upload, cross-posting, scheduled posts, and creating lists/documents/organizations are locked. Verifying email is the fastest way off it. |
/// | `.active` | Normal. Everything works, subject only to subscription tier. |
/// | `.restricted` | Temporarily read-only while under review. No posting, replying, reacting, following, messaging, or creating. Appealable. |
/// | `.suspended` | As `.restricted`, applied by the team. Appealable. |
/// | `.banned` | Closed; cannot sign in — so it is a sign-in failure path, never a banner state. |
///
/// **Unknown values fail open.** `.unknown` is deliberately treated as `.active`
/// by ``AccountStatus/isWriteRestricted`` and friends: a server-side rename of a
/// status string must never brick a paying user's app by silently disabling
/// every write. The raw value is preserved for display and telemetry.
public enum AccountStatus: Sendable, Equatable, Hashable {

    /// A brand-new account on probation — the state every account starts in.
    case new
    /// The normal state.
    case active
    /// Temporarily read-only while under review.
    case restricted
    /// Read-only, applied by the team.
    case suspended
    /// Closed; cannot sign in.
    case banned
    /// A status string this client does not recognise. **Behaves as `.active`.**
    case unknown(String)

    /// Maps the raw wire string to a case, case-insensitively.
    ///
    /// A `nil` or blank field — an older server, or a payload that simply omits
    /// it — maps to `.active`, matching the fail-open rule: absence of evidence
    /// that the account is limited is not evidence that it is.
    public init(raw: String?) {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self = .active
            return
        }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "new": self = .new
        case "active": self = .active
        case "restricted": self = .restricted
        case "suspended": self = .suspended
        case "banned": self = .banned
        default: self = .unknown(raw)
        }
    }

    /// The original wire value, for display or round-tripping.
    public var rawValue: String {
        switch self {
        case .new: return "new"
        case .active: return "active"
        case .restricted: return "restricted"
        case .suspended: return "suspended"
        case .banned: return "banned"
        case .unknown(let raw): return raw
        }
    }

    /// Whether the account is fully read-only: it may browse but may not post,
    /// reply, react, follow, message, or create anything.
    ///
    /// `.unknown` is **not** read-only (fail open).
    public var isWriteRestricted: Bool {
        switch self {
        case .restricted, .suspended: return true
        case .new, .active, .banned, .unknown: return false
        }
    }

    /// Whether the account is on new-account probation, where a *subset* of
    /// actions is locked but plain posting still works (rate-limited).
    public var isOnProbation: Bool { self == .new }

    /// Whether this status warrants the home-timeline status banner. `.active`
    /// and `.unknown` are silent; `.banned` cannot sign in at all, so it is a
    /// sign-in failure path rather than a banner state.
    public var warrantsBanner: Bool {
        switch self {
        case .new, .restricted, .suspended: return true
        case .active, .banned, .unknown: return false
        }
    }
}
