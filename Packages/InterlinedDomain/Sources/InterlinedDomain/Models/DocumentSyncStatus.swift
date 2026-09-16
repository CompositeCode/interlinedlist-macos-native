import Foundation
import InterlinedKit

/// What the Document Sync Agent is doing on one machine, read out of that
/// machine's per-machine app-settings document (GitHub issue #104).
///
/// The agent stores its configuration there rather than in `UserDefaults`, which
/// is what makes this readable at all: before the move, Settings ▸ Applications
/// could list a machine and say nothing whatsoever about what it was set up to
/// do.
///
/// **This type reads keys written by a different codebase.** The agent
/// (`SyncAgent/`) is a clean-room package with no dependency on `InterlinedKit`
/// or `InterlinedDomain`, so the key names below are a wire contract with
/// `DocumentSyncSettingsKeys` in
/// `SyncAgent/Sources/InterlinedListSyncCore/Storage/SyncAgentConfiguration.swift`.
/// Renaming one side without the other does not fail to build — it silently
/// stops the pane reporting anything.
public struct DocumentSyncStatus: Sendable, Equatable {

    /// The wire keys, mirrored from the agent.
    private enum Key {
        static let prefix = "documentSync."
        static let enabled = prefix + "enabled"
        static let folderBookmark = prefix + "folderBookmark"
        static let folderMachineID = prefix + "folderMachineId"
        static let lastSyncAt = prefix + "lastSyncAt"
    }

    /// Whether a sync folder is set up **on the machine that owns this
    /// document**.
    ///
    /// False when the stored bookmark was created on another Mac. That can
    /// happen legitimately — copying a machine's settings to shared, or a new
    /// machine seeding from the main workstation, both move the document across
    /// machines — and a bookmark is meaningless anywhere but where it was made.
    /// Reporting it as configured would promise the user something that is not
    /// true on that computer.
    public let isConfigured: Bool

    /// Whether syncing is switched on. A machine can be configured but paused.
    public let isEnabled: Bool

    /// When that machine last completed a sync cycle, if it has reported one.
    /// Published on a throttle by the agent, so it lags by up to an hour.
    public let lastSyncAt: Date?

    public init(isConfigured: Bool, isEnabled: Bool, lastSyncAt: Date? = nil) {
        self.isConfigured = isConfigured
        self.isEnabled = isEnabled
        self.lastSyncAt = lastSyncAt
    }

    /// Projects the agent's status out of a settings document.
    ///
    /// Returns nil when the document holds none of the agent's keys — that
    /// machine has never run the agent, which is a different statement from
    /// "has it installed but switched off", and the pane says so differently.
    ///
    /// - Parameter deviceID: the machine the document belongs to, used to tell
    ///   its own sync folder from one that travelled in from elsewhere.
    public init?(bag: AppSettingsBag, deviceID: String) {
        guard bag.keys.contains(where: { $0.hasPrefix(Key.prefix) }) else { return nil }
        let bookmark = bag[string: Key.folderBookmark]
        let owner = bag[string: Key.folderMachineID]
        self.init(
            // An unstamped bookmark counts as foreign: nothing has ever written
            // one, so the only way to see one is a document this machine did not
            // produce, and "cannot prove it is ours" must read as "not ours".
            isConfigured: !(bookmark ?? "").isEmpty && owner == deviceID,
            isEnabled: bag[bool: Key.enabled] ?? false,
            lastSyncAt: bag[string: Key.lastSyncAt].flatMap(JSONCoders.parseDate)
        )
    }
}
