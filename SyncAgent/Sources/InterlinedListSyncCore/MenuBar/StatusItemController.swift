import AppKit
import Combine

/// Owns the menu-bar `NSStatusItem` and its menu, rendering from
/// ``SyncStateModel`` and forwarding user actions through injected closures.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {

    /// Actions the menu can trigger; wired by the `AppDelegate`.
    public struct Actions {
        public var syncNow: () -> Void
        public var togglePause: () -> Void
        public var openFolder: () -> Void
        public var openPreferences: () -> Void
        public var openInterlinedList: () -> Void
        public var quit: () -> Void
        public init(
            syncNow: @escaping () -> Void,
            togglePause: @escaping () -> Void,
            openFolder: @escaping () -> Void,
            openPreferences: @escaping () -> Void,
            openInterlinedList: @escaping () -> Void,
            quit: @escaping () -> Void
        ) {
            self.syncNow = syncNow
            self.togglePause = togglePause
            self.openFolder = openFolder
            self.openPreferences = openPreferences
            self.openInterlinedList = openInterlinedList
            self.quit = quit
        }
    }

    private let statusItem: NSStatusItem
    private let state: SyncStateModel
    private let actions: Actions
    private var cancellables = Set<AnyCancellable>()

    private let statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    private let lastSyncedMenuItem = NSMenuItem(title: "Last synced: Never", action: nil, keyEquivalent: "")
    private let pauseMenuItem = NSMenuItem(title: "Pause Syncing", action: nil, keyEquivalent: "")
    private let signInMenuItem = NSMenuItem(title: "Open InterlinedList to Sign In…", action: nil, keyEquivalent: "")

    public init(state: SyncStateModel, actions: Actions) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.state = state
        self.actions = actions
        super.init()
        configureButton()
        buildMenu()
        observeState()
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: state.symbolName,
                accessibilityDescription: "InterlinedList Sync"
            )
            button.image?.isTemplate = true
            button.toolTip = "InterlinedList Sync"
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem.isEnabled = false
        lastSyncedMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(lastSyncedMenuItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("Sync Now", "r", #selector(didTapSyncNow)))
        pauseMenuItem.target = self
        pauseMenuItem.action = #selector(didTapPause)
        menu.addItem(pauseMenuItem)
        menu.addItem(makeItem("Open Sync Folder", "", #selector(didTapOpenFolder)))
        menu.addItem(.separator())

        signInMenuItem.target = self
        signInMenuItem.action = #selector(didTapSignIn)
        signInMenuItem.isHidden = true
        menu.addItem(signInMenuItem)

        menu.addItem(makeItem("Preferences…", ",", #selector(didTapPreferences)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit InterlinedList Sync", "q", #selector(didTapQuit)))

        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ key: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func observeState() {
        state.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        state.$lastSyncedAt
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        configureButton()
        statusMenuItem.title = "Status: \(state.statusTitle)"
        lastSyncedMenuItem.title = state.lastSyncedTitle
        pauseMenuItem.title = state.status == .paused ? "Resume Syncing" : "Pause Syncing"
        let needsSignIn = state.status == .signedOut || state.status == .authExpired
        signInMenuItem.isHidden = !needsSignIn
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) { refresh() }

    // MARK: - Actions

    @objc private func didTapSyncNow() { actions.syncNow() }
    @objc private func didTapPause() { actions.togglePause() }
    @objc private func didTapOpenFolder() { actions.openFolder() }
    @objc private func didTapPreferences() { actions.openPreferences() }
    @objc private func didTapSignIn() { actions.openInterlinedList() }
    @objc private func didTapQuit() { actions.quit() }
}
