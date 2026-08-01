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
