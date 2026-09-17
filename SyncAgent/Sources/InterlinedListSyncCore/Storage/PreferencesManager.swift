import Foundation
import AppKit
import os

/// User-facing settings plus the security-scoped bookmark for the sync folder.
/// `@MainActor` because it is observed by SwiftUI and drives `NSOpenPanel`.
///
/// Two homes, one of them authoritative (GitHub issue #104):
///
/// - **Per-machine app settings** (`…/devices/{deviceId}/settings`) are where
///   the configuration actually lives. That is what `/help/app-settings`
///   describes per-machine storage as being for — a value meaningful on one
///   machine only — and it means a reinstall recovers the user's setup instead
///   of starting from nothing.
/// - **`UserDefaults`** stays as the local mirror and the fallback. It is what
///   the agent runs on before the first successful remote write is confirmed,
///   while offline, and on a machine the main app has not yet published a device
///   id for. Every setter still writes it, so nothing in the agent has to care
///   whether the network is up.
///
/// The bookmark is written to both, but it is only ever *resolved* from
/// `UserDefaults` — a bookmark stamped with another machine is dropped on the
/// way in, so what reaches local storage is always this Mac's own.
@MainActor
public final class PreferencesManager: ObservableObject {

    private enum Key {
        static let pollInterval = "pollIntervalSeconds"
        static let syncEnabled = "syncEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let notifyOnCompletion = "notifyOnCompletion"
        static let notifyOnErrors = "notifyOnErrors"
        static let notifyOnConflicts = "notifyOnConflicts"
        static let launchAtLogin = "launchAtLogin"
        static let folderBookmark = "syncFolderBookmark"
        static let folderPath = "syncFolderPath"
        /// Set only once a migration write has been **confirmed** by the server.
        /// Until then the agent keeps reading `UserDefaults`, which is the whole
        /// point: a half-finished migration must not look like a finished one.
        static let didMigrateToAppSettings = "didMigrateSettingsToAppSettings"
        /// When the reported "last synced" value was last published, so the
        /// hourly throttle survives a relaunch instead of firing a write on
        /// every launch.
        static let lastSyncPublishedAt = "lastSyncPublishedAt"
    }

    private let defaults: UserDefaults
    private let remote: RemoteConfigurationStore?
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "Preferences")
    private var accessingURL: URL?

    /// Coalescing window for remote writes. Each toggle in the preferences
    /// window is one `didSet`; without this, dragging the poll-interval slider
    /// would issue a settings PUT per step.
    private let remoteSaveDebounce: Duration
    private var pendingSave: Task<Void, Never>?
    /// Suppresses the write-back that applying a freshly-read remote
    /// configuration would otherwise trigger.
    private var isApplyingRemote = false

    @Published public var pollIntervalSeconds: TimeInterval {
        didSet { defaults.set(pollIntervalSeconds, forKey: Key.pollInterval); scheduleRemoteSave() }
    }
    @Published public var syncEnabled: Bool {
        didSet { defaults.set(syncEnabled, forKey: Key.syncEnabled); scheduleRemoteSave() }
    }
    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled); scheduleRemoteSave() }
    }
    @Published public var notifyOnCompletion: Bool {
        didSet { defaults.set(notifyOnCompletion, forKey: Key.notifyOnCompletion); scheduleRemoteSave() }
    }
    @Published public var notifyOnErrors: Bool {
        didSet { defaults.set(notifyOnErrors, forKey: Key.notifyOnErrors); scheduleRemoteSave() }
    }
    @Published public var notifyOnConflicts: Bool {
        didSet { defaults.set(notifyOnConflicts, forKey: Key.notifyOnConflicts); scheduleRemoteSave() }
    }
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin); scheduleRemoteSave() }
    }
    /// Display-only path of the chosen folder (the source of truth is the bookmark).
    @Published public private(set) var syncFolderPath: String?

    /// When the last completed sync cycle was reported to app settings.
    /// Reporting only — the engine's own cursor lives in the on-disk ledger.
    private var lastSyncAt: Date?
    private var lastSyncPublishedAt: Date?

    public init(
        defaults: UserDefaults = .standard,
        remote: RemoteConfigurationStore? = nil,
        remoteSaveDebounce: Duration = .seconds(2)
    ) {
        self.defaults = defaults
        self.remote = remote
        self.remoteSaveDebounce = remoteSaveDebounce
        let stored = defaults.object(forKey: Key.pollInterval) as? TimeInterval
        self.pollIntervalSeconds = stored.map {
            min(max($0, SyncConfiguration.minPollInterval), SyncConfiguration.maxPollInterval)
        } ?? SyncConfiguration.defaultPollInterval
        self.syncEnabled = (defaults.object(forKey: Key.syncEnabled) as? Bool) ?? true
        self.notificationsEnabled = (defaults.object(forKey: Key.notificationsEnabled) as? Bool) ?? true
        self.notifyOnCompletion = (defaults.object(forKey: Key.notifyOnCompletion) as? Bool) ?? false
        self.notifyOnErrors = (defaults.object(forKey: Key.notifyOnErrors) as? Bool) ?? true
        self.notifyOnConflicts = (defaults.object(forKey: Key.notifyOnConflicts) as? Bool) ?? true
        self.launchAtLogin = (defaults.object(forKey: Key.launchAtLogin) as? Bool) ?? false
        self.syncFolderPath = defaults.string(forKey: Key.folderPath)
        self.lastSyncPublishedAt = defaults.object(forKey: Key.lastSyncPublishedAt) as? Date
    }

    // MARK: - Per-machine app settings

    /// True once a configuration write to per-machine app settings has been
    /// confirmed. Until then `UserDefaults` is the fallback the agent runs on.
    public var hasMigratedToAppSettings: Bool {
        defaults.bool(forKey: Key.didMigrateToAppSettings)
    }

    /// Brings this machine's configuration in line with per-machine app
    /// settings, migrating the local one up exactly once if the server has none.
    ///
    /// Call once at launch, before starting the engine: a remote configuration
    /// may name a different sync folder than the local mirror does.
    public func synchronize() async {
        guard let remote, let machineID = await remote.currentDeviceID else { return }

        let state = await remote.load()
        let resolution = ConfigurationResolver.resolve(
            remote: state,
            local: configuration(machineID: machineID),
            hasMigrated: hasMigratedToAppSettings
        )
        apply(resolution.configuration)

        if resolution.shouldMigrate {
            await write(configuration(machineID: machineID), to: remote)
            return
        }
        // Applying a stored configuration can legitimately leave this machine
        // holding more than the server does — a folder chosen while offline is
        // kept rather than cleared (see `apply`). Push the difference back so the
        // two agree, instead of silently diverging until the next toggle.
        let effective = configuration(machineID: machineID)
        if case .stored(let stored) = state, stored != effective {
            await write(effective, to: remote)
        }
    }

    /// Reports a completed sync cycle, throttled.
    ///
    /// Status, not configuration: Settings ▸ Applications shows it so a machine
    /// can say what it is doing, and nothing reads it back. Writing it every
    /// cycle would be a settings PUT a minute, per machine, forever.
    ///
    /// Returns the publishing task, or nil when the throttle swallowed the
    /// report. Callers in the agent ignore it; tests await it, so the publish is
    /// observable without sleeping on a timer.
    @discardableResult
    public func recordSync(at date: Date) -> Task<Void, Never>? {
        lastSyncAt = date
        guard let remote else { return nil }
        if let published = lastSyncPublishedAt,
           date.timeIntervalSince(published) < SyncConfiguration.lastSyncPublishInterval {
            return nil
        }
        lastSyncPublishedAt = date
        defaults.set(date, forKey: Key.lastSyncPublishedAt)
        return Task { [weak self] in
            guard let self, let machineID = await remote.currentDeviceID else { return }
            await self.write(self.configuration(machineID: machineID), to: remote)
        }
    }

    /// The current configuration as stored remotely.
    func configuration(machineID: String) -> SyncAgentConfiguration {
        SyncAgentConfiguration(
            syncEnabled: syncEnabled,
            pollIntervalSeconds: pollIntervalSeconds,
            launchAtLogin: launchAtLogin,
            notificationsEnabled: notificationsEnabled,
            notifyOnCompletion: notifyOnCompletion,
            notifyOnErrors: notifyOnErrors,
            notifyOnConflicts: notifyOnConflicts,
            folder: defaults.data(forKey: Key.folderBookmark).map {
                SyncFolderReference(
                    bookmark: $0,
                    displayPath: defaults.string(forKey: Key.folderPath) ?? "",
                    machineID: machineID
                )
            },
            lastSyncAt: lastSyncAt
        )
    }

    /// Adopts a configuration read from per-machine app settings.
    ///
    /// The folder is only ever *added*, never cleared. A stored configuration
    /// with no folder means one had not been chosen when it was written, or that
    /// it belonged to another machine and was dropped on the way in — neither is
    /// evidence the user unset anything, and there is no UI to unset a folder,
    /// only to change it. Clearing would throw away a folder chosen while this
    /// machine was offline.
    func apply(_ configuration: SyncAgentConfiguration) {
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        pollIntervalSeconds = configuration.pollIntervalSeconds
        syncEnabled = configuration.syncEnabled
        launchAtLogin = configuration.launchAtLogin
        notificationsEnabled = configuration.notificationsEnabled
        notifyOnCompletion = configuration.notifyOnCompletion
        notifyOnErrors = configuration.notifyOnErrors
        notifyOnConflicts = configuration.notifyOnConflicts
        lastSyncAt = configuration.lastSyncAt ?? lastSyncAt

        if let folder = configuration.folder {
            defaults.set(folder.bookmark, forKey: Key.folderBookmark)
            defaults.set(folder.displayPath, forKey: Key.folderPath)
            syncFolderPath = folder.displayPath
        }
    }

    private func write(_ configuration: SyncAgentConfiguration, to remote: RemoteConfigurationStore) async {
        do {
            try await remote.save(configuration)
            defaults.set(true, forKey: Key.didMigrateToAppSettings)
        } catch {
            // Deliberately silent. The agent has no window open most of the
            // time, and a failed settings write costs the user nothing: the
            // local mirror is still authoritative until a write is confirmed,
            // and the next change tries again.
            logger.error("Per-machine settings write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleRemoteSave() {
        guard !isApplyingRemote, let remote else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.remoteSaveDebounce)
            guard !Task.isCancelled, let machineID = await remote.currentDeviceID else { return }
            await self.write(self.configuration(machineID: machineID), to: remote)
        }
    }

    // MARK: - Sync folder

    /// Prompts the user to choose a sync folder and stores a security-scoped
    /// bookmark. Returns the chosen URL (already `startAccessing`-ed).
    public func chooseSyncFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Sync Folder"
        panel.message = "Choose a folder to sync your InterlinedList documents into (e.g. an Obsidian vault)."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        store(folder: url)
        return startAccessing()
    }

    private func store(folder url: URL) {
        if let bookmark = SecurityScopedAccess.makeBookmark(for: url) {
            defaults.set(bookmark, forKey: Key.folderBookmark)
        }
        defaults.set(url.path, forKey: Key.folderPath)
        syncFolderPath = url.path
        // Not a `@Published` setter, so it has no `didSet` to ride on — and a
        // folder change is the single most valuable thing to get stored
        // remotely, since it is what a reinstall needs back.
        scheduleRemoteSave()
    }

    /// Resolves the stored bookmark and begins accessing it. Returns the URL, or
    /// `nil` if no folder was chosen / the bookmark is unresolvable.
    @discardableResult
    public func startAccessing() -> URL? {
        if let accessingURL { return accessingURL }
        guard let data = defaults.data(forKey: Key.folderBookmark),
              let resolved = SecurityScopedAccess.resolve(data) else { return nil }
        if resolved.url.startAccessingSecurityScopedResource() {
            accessingURL = resolved.url
            syncFolderPath = resolved.url.path
            return resolved.url
        }
        return nil
    }

    public func stopAccessing() {
        accessingURL?.stopAccessingSecurityScopedResource()
        accessingURL = nil
    }

    public var hasSyncFolder: Bool {
        defaults.data(forKey: Key.folderBookmark) != nil
    }

    /// Reveals the sync folder in Finder.
    public func revealSyncFolder() {
        guard let path = syncFolderPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
