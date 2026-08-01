import AppKit
import SwiftUI
import os

/// Assembles the agent at launch, drives the engine, and bridges its events to
/// the menu-bar UI. Runs as an `LSUIElement` agent (no Dock icon).
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "AppDelegate")

    private let prefs = PreferencesManager()
    private let state = SyncStateModel()
    private let notifications = NotificationManager()
    private let loginItems: any LoginItemManaging = LoginItemManager()
    private let tokenStore = SharedTokenStore()

    private var engine: SyncEngine?
    private var statusItem: StatusItemController?
    private var eventTask: Task<Void, Never>?
    private var preferencesWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        notifications.requestAuthorization()
        prefs.launchAtLogin = loginItems.isEnabled()

        statusItem = StatusItemController(state: state, actions: makeActions())

        if !prefs.hasSyncFolder {
            // First run without a folder: let the user pick one.
            openPreferences()
        } else if tokenStore.hasToken {
            startEngine()
        } else {
            state.status = .signedOut
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        eventTask?.cancel()
        let engine = engine
        Task { await engine?.stop() }
        prefs.stopAccessing()
    }

    // MARK: - Engine lifecycle

    private func startEngine() {
        guard let folder = prefs.startAccessing() else {
            state.status = .error("Sync folder is unavailable")
            return
        }
        guard tokenStore.hasToken else {
            state.status = .signedOut
            return
        }

        // Tear down any prior engine (folder change / re-sign-in).
        eventTask?.cancel()
        let previous = engine
        Task { await previous?.stop() }

        let mapper = DocumentMapper(rootURL: folder)
        let api = SyncAPIClient(tokenProvider: tokenStore)
        let ledger = FileLedgerStore(url: FileLedgerStore.defaultURL())
        let watcher = FSEventsWatcher(url: folder)
        let network = NetworkMonitor()
        let engine = SyncEngine(
            api: api, mapper: mapper, ledgerStore: ledger,
            pollInterval: prefs.pollIntervalSeconds,
            watcher: watcher, network: network
        )
        self.engine = engine

        eventTask = Task { [weak self] in
            let stream = await engine.events
            for await event in stream {
                await self?.handle(event)
            }
        }

        Task {
            await engine.start()
            if !prefs.syncEnabled { await engine.pause() }
        }
    }

    private func handle(_ event: SyncEvent) {
        state.apply(event)
        switch event {
        case .cycleCompleted(let summary):
            if prefs.notificationsEnabled && prefs.notifyOnCompletion {
                notifications.notifySyncCompleted(summary)
            }
        case .conflictCreated(let fileName):
            if prefs.notificationsEnabled && prefs.notifyOnConflicts {
                notifications.notifyConflict(fileName: fileName)
            }
        case .authRequired:
            if prefs.notificationsEnabled { notifications.notifyAuthRequired() }
        case .statusChanged(let status):
            if case .error(let message) = status,
               prefs.notificationsEnabled, prefs.notifyOnErrors {
                notifications.notifyError(message)
            }
        }
    }

    // MARK: - Actions

    private func makeActions() -> StatusItemController.Actions {
        StatusItemController.Actions(
            syncNow: { [weak self] in self?.syncNow() },
            togglePause: { [weak self] in self?.togglePause() },
            openFolder: { [weak self] in self?.prefs.revealSyncFolder() },
            openPreferences: { [weak self] in self?.openPreferences() },
            openInterlinedList: { [weak self] in self?.openMainApp() },
            quit: { NSApp.terminate(nil) }
        )
    }

    private func syncNow() {
        guard let engine else {
            // No engine yet (missing folder/token): try to bring it up.
            if tokenStore.hasToken, prefs.hasSyncFolder { startEngine() }
            return
        }
        Task { await engine.syncNow(trigger: .manual) }
    }

    private func togglePause() {
        guard let engine else { return }
        Task {
            if await engine.currentStatus() == .paused {
                prefs.syncEnabled = true
                await engine.resume()
            } else {
                prefs.syncEnabled = false
                await engine.pause()
            }
        }
    }

    private func openMainApp() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.interlinedlist.macos") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let web = URL(string: "https://interlinedlist.com") {
            NSWorkspace.shared.open(web)
        }
    }

    // MARK: - Preferences window

    private func openPreferences() {
        if preferencesWindow == nil {
            let actions = PreferencesActions(
                chooseFolder: { [weak self] in self?.chooseFolder() },
                pollIntervalChanged: { [weak self] value in
                    guard let engine = self?.engine else { return }
                    Task { await engine.setPollInterval(value) }
                },
                launchAtLoginChanged: { [weak self] enabled in self?.setLaunchAtLogin(enabled) },
                syncEnabledChanged: { [weak self] enabled in self?.setSyncEnabled(enabled) },
                syncNow: { [weak self] in self?.syncNow() },
                openInterlinedList: { [weak self] in self?.openMainApp() }
            )
            let view = PreferencesView(prefs: prefs, state: state, actions: actions)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "InterlinedList Sync"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    private func chooseFolder() {
        guard prefs.chooseSyncFolder() != nil else { return }
        // (Re)start the engine against the new folder.
        if tokenStore.hasToken {
            startEngine()
        } else {
            state.status = .signedOut
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try loginItems.enable() } else { try loginItems.disable() }
        } catch {
            logger.error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
            prefs.launchAtLogin = loginItems.isEnabled()
        }
    }

    private func setSyncEnabled(_ enabled: Bool) {
        guard let engine else { return }
        Task {
            if enabled { await engine.resume() } else { await engine.pause() }
        }
    }
}
