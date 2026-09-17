import Foundation

/// The keys the agent's configuration occupies inside a per-machine app-settings
/// document (GitHub issue #104).
///
/// **This list is a wire contract with the main app.** `InterlinedDomain`'s
/// `DocumentSyncStatus` reads the same keys out of the same document so
/// Settings ▸ Applications can report what a machine is doing. The two are
/// independent codebases — this package deliberately does not depend on
/// `InterlinedKit`/`InterlinedDomain` — so a rename here without a matching
/// rename there silently stops the pane reporting anything. Change both.
///
/// Every key is prefixed. The document is **shared** with the main app's own
/// per-machine settings, and the PUT replaces it wholesale, so an unprefixed
/// `enabled` would be one careless commit away from meaning two things.
public enum DocumentSyncSettingsKeys {
    /// Prefix identifying keys this agent owns. Everything else in the document
    /// belongs to someone else and must survive our writes untouched.
    public static let prefix = "documentSync."

    public static let schemaVersion = prefix + "schemaVersion"
    public static let enabled = prefix + "enabled"
    public static let pollIntervalSeconds = prefix + "pollIntervalSeconds"
    public static let launchAtLogin = prefix + "launchAtLogin"
    public static let notificationsEnabled = prefix + "notificationsEnabled"
    public static let notifyOnCompletion = prefix + "notifyOnCompletion"
    public static let notifyOnErrors = prefix + "notifyOnErrors"
    public static let notifyOnConflicts = prefix + "notifyOnConflicts"
    /// Human-readable path of the sync folder. **Display only** — a sandboxed
    /// process cannot reopen a user-chosen folder from a path string.
    public static let folderPath = prefix + "folderPath"
    /// Base64 of the security-scoped bookmark. The actual key to the folder.
    public static let folderBookmark = prefix + "folderBookmark"
    /// The device id of the Mac that created the bookmark.
    public static let folderMachineID = prefix + "folderMachineId"
    /// ISO-8601 timestamp of the last completed sync cycle. Status, not
    /// configuration — see ``SyncConfiguration/lastSyncPublishInterval``.
    public static let lastSyncAt = prefix + "lastSyncAt"
}

// MARK: - The sync folder

/// A chosen sync folder: the bookmark that actually opens it, the path to show
/// a human, and the machine both belong to.
///
/// The machine stamp is not redundant. Per-machine settings are *meant* to stay
/// on one Mac, but two documented paths move a document across machines anyway:
/// Settings ▸ Applications can copy a machine's settings to the account-wide
/// document, and a brand-new machine's first sign-in seeds from the main
/// workstation. Either one can hand this Mac a bookmark another Mac created.
///
/// Resolving a foreign bookmark does not fail cleanly — at best it resolves to a
/// path that does not exist here, at worst to an unrelated folder with the same
/// name, which the agent would then start writing documents into. So a foreign
/// reference is dropped on read and the machine reports itself unconfigured,
/// which is both true and recoverable: the user picks a folder.
public struct SyncFolderReference: Sendable, Equatable {
    /// Security-scoped bookmark data. Only meaningful on ``machineID``.
    public let bookmark: Data
    /// Where the folder lives, for display. Never used to open anything.
    public let displayPath: String
    /// The device id of the Mac this bookmark was created on.
    public let machineID: String

    public init(bookmark: Data, displayPath: String, machineID: String) {
        self.bookmark = bookmark
        self.displayPath = displayPath
        self.machineID = machineID
    }
}

// MARK: - The configuration

/// Everything the Document Sync Agent needs to know about itself, in the shape
/// it is stored in per-machine app settings.
///
/// This is the complete set of state the agent used to keep in `UserDefaults`,
/// enumerated from `PreferencesManager` rather than guessed. Two things named in
/// GitHub issue #104 are deliberately **not** here:
///
/// - **The sync ledger's cursor.** `LedgerData.lastSyncAt` is the delta cursor,
///   and it is only meaningful next to the per-document entries stored in the
///   same file. Uploading the cursor alone would let a machine resume from a
///   cursor its ledger cannot account for, and conclude nothing had changed.
///   ``lastSyncAt`` here is a *report* of when the last cycle finished, read by
///   Settings ▸ Applications and never fed back into the engine.
/// - **A conflict policy.** There is not one to move: ``ConflictResolver`` is a
///   fixed remote-wins decision table with no user-facing setting. Inventing a
///   stored policy to satisfy the migration would create a setting nothing
///   reads.
public struct SyncAgentConfiguration: Sendable, Equatable {

    public var syncEnabled: Bool
    public var pollIntervalSeconds: TimeInterval
    public var launchAtLogin: Bool
    public var notificationsEnabled: Bool
    public var notifyOnCompletion: Bool
    public var notifyOnErrors: Bool
    public var notifyOnConflicts: Bool
    /// The chosen folder, or nil when this machine has none.
    public var folder: SyncFolderReference?
    /// When the last sync cycle finished, for reporting only.
    public var lastSyncAt: Date?

    public init(
        syncEnabled: Bool = true,
        pollIntervalSeconds: TimeInterval = SyncConfiguration.defaultPollInterval,
        launchAtLogin: Bool = false,
        notificationsEnabled: Bool = true,
        notifyOnCompletion: Bool = false,
        notifyOnErrors: Bool = true,
        notifyOnConflicts: Bool = true,
        folder: SyncFolderReference? = nil,
        lastSyncAt: Date? = nil
    ) {
        self.syncEnabled = syncEnabled
        self.pollIntervalSeconds = pollIntervalSeconds
        self.launchAtLogin = launchAtLogin
        self.notificationsEnabled = notificationsEnabled
        self.notifyOnCompletion = notifyOnCompletion
        self.notifyOnErrors = notifyOnErrors
        self.notifyOnConflicts = notifyOnConflicts
        self.folder = folder
        self.lastSyncAt = lastSyncAt
    }

    // MARK: - Reading a stored document

    /// Projects the agent's configuration out of a settings payload.
    ///
    /// Returns nil when the payload holds none of this agent's keys — the main
    /// app may well have written per-machine settings of its own, but a document
    /// without a `documentSync.` key has never been written by the agent, and
    /// treating it as a stored-but-default configuration would suppress the
    /// migration that is supposed to run exactly once.
    ///
    /// - Parameter thisMachineID: the device id of the Mac doing the reading.
    ///   A folder stamped with any other machine is dropped; see
    ///   ``SyncFolderReference``.
    public init?(settings: [String: SettingsValue], thisMachineID: String) {
        let keys = DocumentSyncSettingsKeys.self
        guard settings.keys.contains(where: { $0.hasPrefix(keys.prefix) }) else { return nil }

        let defaults = SyncAgentConfiguration()
        self.init(
            syncEnabled: settings[keys.enabled]?.boolValue ?? defaults.syncEnabled,
            // Clamped on read, not just on write: a value stored by a build with
            // different bounds must not make this one poll every second.
            pollIntervalSeconds: (settings[keys.pollIntervalSeconds]?.doubleValue)
                .map { min(max($0, SyncConfiguration.minPollInterval), SyncConfiguration.maxPollInterval) }
                ?? defaults.pollIntervalSeconds,
            launchAtLogin: settings[keys.launchAtLogin]?.boolValue ?? defaults.launchAtLogin,
            notificationsEnabled: settings[keys.notificationsEnabled]?.boolValue ?? defaults.notificationsEnabled,
            notifyOnCompletion: settings[keys.notifyOnCompletion]?.boolValue ?? defaults.notifyOnCompletion,
            notifyOnErrors: settings[keys.notifyOnErrors]?.boolValue ?? defaults.notifyOnErrors,
            notifyOnConflicts: settings[keys.notifyOnConflicts]?.boolValue ?? defaults.notifyOnConflicts,
            folder: Self.folder(from: settings, thisMachineID: thisMachineID),
            lastSyncAt: settings[keys.lastSyncAt]?.stringValue.flatMap(JSONCoding.parseISO8601)
        )
    }

    private static func folder(
        from settings: [String: SettingsValue],
        thisMachineID: String
    ) -> SyncFolderReference? {
        let keys = DocumentSyncSettingsKeys.self
        guard let encoded = settings[keys.folderBookmark]?.stringValue,
              let bookmark = Data(base64Encoded: encoded),
              !bookmark.isEmpty
        else { return nil }

        // An unstamped bookmark is treated as foreign too. Nothing has ever
        // written one, so the only way to see one is a document this agent did
        // not produce — and "cannot prove it is ours" has to read as "not ours",
        // because the failure it prevents is syncing into the wrong folder.
        guard let machineID = settings[keys.folderMachineID]?.stringValue,
              machineID == thisMachineID
        else { return nil }

        return SyncFolderReference(
            bookmark: bookmark,
            displayPath: settings[keys.folderPath]?.stringValue ?? "",
            machineID: machineID
        )
    }

    // MARK: - Writing a stored document

    /// Overlays this configuration onto an existing settings payload.
    ///
    /// The PUT **replaces** the document rather than merging it (verified live:
    /// a write carrying only `theme` deleted a stored `sidebarWidth`), so the
    /// payload handed to it has to be the whole document. Keys outside the
    /// `documentSync.` namespace are copied through untouched — they belong to
    /// the main app, or to a newer build of this one, and dropping them would
    /// make every agent write silently delete settings it never owned.
    ///
    /// Keys inside the namespace are rebuilt from scratch, so unsetting a folder
    /// removes its keys instead of leaving a stale bookmark behind.
    public func apply(to existing: [String: SettingsValue]) -> [String: SettingsValue] {
        let keys = DocumentSyncSettingsKeys.self
        var payload = existing.filter { !$0.key.hasPrefix(keys.prefix) }

        payload[keys.schemaVersion] = .number(Double(SyncConfiguration.settingsSchemaVersion))
        payload[keys.enabled] = .bool(syncEnabled)
        payload[keys.pollIntervalSeconds] = .number(pollIntervalSeconds)
        payload[keys.launchAtLogin] = .bool(launchAtLogin)
        payload[keys.notificationsEnabled] = .bool(notificationsEnabled)
        payload[keys.notifyOnCompletion] = .bool(notifyOnCompletion)
        payload[keys.notifyOnErrors] = .bool(notifyOnErrors)
        payload[keys.notifyOnConflicts] = .bool(notifyOnConflicts)

        if let folder {
            payload[keys.folderBookmark] = .string(folder.bookmark.base64EncodedString())
            payload[keys.folderPath] = .string(folder.displayPath)
            payload[keys.folderMachineID] = .string(folder.machineID)
        }
        if let lastSyncAt {
            payload[keys.lastSyncAt] = .string(JSONCoding.iso8601String(lastSyncAt))
        }
        return payload
    }
}
