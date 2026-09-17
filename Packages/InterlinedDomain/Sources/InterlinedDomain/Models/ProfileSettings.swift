import Foundation

// MARK: - AppTheme

/// The appearance the account prefers (GitHub #46 / G34).
///
/// The web offers exactly three. **The server validates none of them** —
/// probed live 2026-09-15, `PATCH /api/user/update` accepted `"system"`,
/// `"dark"`, `"light"`, `"auto"` and `"nonsense"` alike, storing and returning
/// each verbatim.
///
/// That asymmetry is the whole design of this type: the client **writes** only
/// the three it understands, and **reads** anything without failing. `.unknown`
/// is therefore not defensive padding — it is the documented behaviour of an
/// unvalidated field, and an account whose theme was set elsewhere must not
/// break the settings pane.
public enum AppTheme: Sendable, Equatable, Hashable {
    case system
    case light
    case dark
    /// A value the server holds that this client does not model. Preserved
    /// verbatim so a save of *other* fields cannot silently rewrite it.
    case unknown(String)

    public init(wireToken: String) {
        switch wireToken.lowercased() {
        case "system": self = .system
        case "light": self = .light
        case "dark": self = .dark
        default: self = .unknown(wireToken)
        }
    }

    public var wireToken: String {
        switch self {
        case .system: return "system"
        case .light: return "light"
        case .dark: return "dark"
        case .unknown(let raw): return raw
        }
    }

    /// The three the picker offers. `.unknown` is deliberately absent: it is a
    /// value to preserve, never one to choose.
    public static let selectable: [AppTheme] = [.system, .light, .dark]

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .unknown(let raw): return raw
        }
    }
}

// MARK: - ProfileSettings

/// The editable identity half of the account (GitHub #46 / G34) — the fields
/// `/help/settings` groups under **Profile settings**.
///
/// Kept separate from `UserSettings`, which models the *behavioural*
/// preferences (feed page size, tray limit, default visibility). Same account,
/// same PATCH route, different question: this is "who am I", that is "how does
/// the app behave".
public struct ProfileSettings: Sendable, Equatable {

    /// The account's own per-message character cap.
    ///
    /// Server-enforced range, probed live 2026-09-15: outside `1...10000` the
    /// PATCH is rejected with `400 "maxMessageLength must be a positive integer
    /// between 1 and 10000"`.
    public static let maxMessageLengthRange: ClosedRange<Int> = 1...10_000

    /// The longest a bio may be before the client refuses to send it.
    ///
    /// The server states no bio limit, so this is a **client-side sanity
    /// bound**, not a mirror of a server rule — named as such so nobody later
    /// reads it as verified.
    public static let bioLengthLimit = 500

    /// How you appear to others. Empty means "fall back to the username", which
    /// is what the server does, so an empty string is a legitimate value rather
    /// than a validation failure.
    public var displayName: String

    /// The short description on the public profile.
    public var bio: String

    /// The account's appearance preference.
    public var theme: AppTheme

    /// The account's own message cap. Always within `maxMessageLengthRange` —
    /// the setter clamps, so no caller can route around the server's rule and
    /// earn a 400.
    public var maxMessageLength: Int {
        get { storedMaxMessageLength }
        set { storedMaxMessageLength = Self.clamp(newValue, to: Self.maxMessageLengthRange) }
    }

    private var storedMaxMessageLength: Int

    /// The avatar currently in use. Read-only here — it is changed through its
    /// own upload/from-URL calls, not through the PATCH body.
    public var avatarURL: URL?

    /// The published profile location, when the account has one.
    ///
    /// **Read-only, deliberately** (GitHub #57, #91). These coordinates can be
    /// set through `PATCH /api/user/update` and **cannot be cleared through any
    /// route**: `null`, `""`, `false` and out-of-range values are all rejected
    /// `400`, and every speculative clear key returns `200` while changing
    /// nothing. Offering a setter without a clear would make this client a way
    /// to publish an approximate home location on a public profile that the
    /// user can never take back — so until clearing exists, macOS shows the
    /// value and does not write it.
    public let location: ProfileLocation?

    public init(
        displayName: String = "",
        bio: String = "",
        theme: AppTheme = .system,
        maxMessageLength: Int = 666,
        avatarURL: URL? = nil,
        location: ProfileLocation? = nil
    ) {
        self.displayName = displayName
        self.bio = bio
        self.theme = theme
        self.storedMaxMessageLength = Self.clamp(maxMessageLength, to: Self.maxMessageLengthRange)
        self.avatarURL = avatarURL
        self.location = location
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - ProfileLocation

/// A published profile location. Read-only on macOS — see
/// `ProfileSettings.location`.
public struct ProfileLocation: Sendable, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double?, longitude: Double?) {
        // A half-set pair is not a location. The server can hold one without the
        // other, and rendering "47.6, —" would be worse than rendering nothing.
        guard let latitude, let longitude else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Formatted for display at the precision the field actually carries.
    public var displayText: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}
