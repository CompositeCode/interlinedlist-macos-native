import Foundation
import AppKit

/// User-facing settings, persisted to `UserDefaults`, plus the security-scoped
/// bookmark for the sync folder. `@MainActor` because it is observed by SwiftUI
/// and drives `NSOpenPanel`.
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
    }

    private let defaults: UserDefaults
    private var accessingURL: URL?

    @Published public var pollIntervalSeconds: TimeInterval {
        didSet { defaults.set(pollIntervalSeconds, forKey: Key.pollInterval) }
    }
    @Published public var syncEnabled: Bool {
        didSet { defaults.set(syncEnabled, forKey: Key.syncEnabled) }
    }
    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }
    @Published public var notifyOnCompletion: Bool {
        didSet { defaults.set(notifyOnCompletion, forKey: Key.notifyOnCompletion) }
    }
    @Published public var notifyOnErrors: Bool {
        didSet { defaults.set(notifyOnErrors, forKey: Key.notifyOnErrors) }
    }
    @Published public var notifyOnConflicts: Bool {
        didSet { defaults.set(notifyOnConflicts, forKey: Key.notifyOnConflicts) }
    }
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }
    /// Display-only path of the chosen folder (the source of truth is the bookmark).
    @Published public private(set) var syncFolderPath: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
