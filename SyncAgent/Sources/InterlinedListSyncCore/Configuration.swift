import Foundation

/// Static configuration shared across the agent. Values that must match the
/// main app (Keychain service/account/access-group, team id) live here so the
/// sharing contract is explicit and in one place.
public enum SyncConfiguration {

    /// API origin. Endpoint paths append `/api/...`.
    public static let apiBaseURL = URL(string: "https://interlinedlist.com")!

    public static let bundleIdentifier = "com.interlinedlist.macos.sync"

    /// Apple Developer team id (from the main app's project config). Used to
    /// build the fully-qualified shared Keychain access group.
    public static let teamIdentifier = "BJA9558E4B"

    // MARK: - Shared Keychain (must match the main app)

    /// `kSecAttrService` of the bearer-token item the main app writes.
    public static let tokenService = "com.interlinedlist.macos.bearer-token"
    /// `kSecAttrAccount` of that item.
    public static let tokenAccount = "default"
    /// Bare shared access-group name (as it appears in the entitlement after the
    /// `$(AppIdentifierPrefix)` prefix).
    public static let sharedAccessGroupSuffix = "com.interlinedlist.shared"
    /// Fully-qualified access group used in Keychain queries.
    public static let sharedAccessGroup = "\(teamIdentifier).\(sharedAccessGroupSuffix)"

    /// `kSecAttrService` of the app-settings **device id** the main app
    /// publishes into the same shared group (GitHub issue #104).
    ///
    /// Must match the main app's `DeviceIdentity.sharedStore`. The id is not a
    /// secret; the Keychain is simply the cross-process channel both sandboxes
    /// are already entitled to — the agent has its own bundle identifier and so
    /// its own `UserDefaults` domain, which is why the value cannot just be a
    /// shared preference.
    public static let deviceIDService = "com.interlinedlist.macos.device-id"
    /// `kSecAttrAccount` of that item.
    public static let deviceIDAccount = "default"

    // MARK: - Per-machine app settings (GitHub issue #104)

    /// The app-settings namespace this client's settings live under. **Must not
    /// change** — it is the key every stored setting is filed under, and a new
    /// one orphans all of them. Matches the main app's
    /// `AppEnvironment.appSettingsKey`.
    public static let appSettingsKey = "interlinedlist-macos"

    /// Version stamped on the settings payload this build writes, so a future
    /// build can tell what it is reading before it interprets it.
    public static let settingsSchemaVersion = 1

    /// How stale a published "last synced" timestamp is allowed to get.
    ///
    /// The timestamp is status, not configuration: it exists so Settings ▸
    /// Applications can say what a machine is actually doing rather than only
    /// that it exists. Writing it on every poll cycle would mean a settings PUT
    /// every minute per machine, forever, to move a value nobody is watching in
    /// real time — so it rides an hourly throttle instead.
    public static let lastSyncPublishInterval: TimeInterval = 3600

    // MARK: - Filesystem correlation

    /// Extended-attribute key holding the server document id on each `.md` file.
    public static let documentIDAttribute = "com.interlinedlist.sync.documentID"

    /// Suffix used for locally-preserved conflict copies: `<base>.conflict-<ts>.md`.
    public static let conflictInfix = "conflict-"

    // MARK: - Login item

    public static let loginItemIdentifier = "com.interlinedlist.macos.sync"

    // MARK: - Sync cadence

    public static let defaultPollInterval: TimeInterval = 60
    public static let minPollInterval: TimeInterval = 30
    public static let maxPollInterval: TimeInterval = 600
    /// Run a full `GET /api/documents` reconciliation every N delta cycles to
    /// catch deletions the delta endpoint drops silently.
    public static let fullReconcileEveryNCycles = 10
    /// Ceiling for exponential backoff on repeated failures.
    public static let maxBackoff: TimeInterval = 300

    public static let logSubsystem = "com.interlinedlist.macos.sync"
}
