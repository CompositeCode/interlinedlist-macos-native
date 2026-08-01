// SyncServiceController
//
// Controls the bundled document-sync background agent
// (`com.interlinedlist.macos.sync`) from the main app's Settings. The agent is
// embedded at `Contents/Library/LoginItems/InterlinedListSync.app` and launched
// by a bundled LaunchAgent plist at `Contents/Library/LaunchAgents/…` via
// `SMAppService.agent` — registering it starts the agent immediately (RunAtLoad)
// and re-launches it at every login, so it runs autonomously of this app.
//
// Pure `ServiceManagement` — no AppKit — so it stays within the App target's
// SwiftUI-only constraint (decision: the sync agent is a *separate* process and
// may use AppKit; this controller may not).

import Foundation
import ServiceManagement
import os

@MainActor
final class SyncServiceController: ObservableObject {

    /// Fully-qualified shared Keychain access group (team prefix + suffix). Must
    /// match the sync agent's `SyncConfiguration.sharedAccessGroup` and the
    /// `keychain-access-groups` entitlement of both apps.
    static let sharedKeychainAccessGroup = "BJA9558E4B.com.interlinedlist.shared"

    /// Name of the bundled LaunchAgent plist (in `Contents/Library/LaunchAgents`).
    static let agentPlistName = "com.interlinedlist.macos.sync.plist"

    private let logger = Logger(subsystem: "com.interlinedlist.macos", category: "SyncService")
    private var service: SMAppService { .agent(plistName: Self.agentPlistName) }

    @Published private(set) var status: SMAppService.Status
    @Published var lastErrorMessage: String?

    init() {
        status = SMAppService.agent(plistName: Self.agentPlistName).status
    }

    var isEnabled: Bool { status == .enabled }

    func refresh() { status = service.status }

    /// Enables (registers + starts) the background sync agent.
    func enable() {
        do {
            try service.register()
            lastErrorMessage = nil
        } catch {
            logger.error("Failed to enable sync agent: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
        refresh()
    }

    /// Disables (unregisters + stops) the background sync agent.
    func disable() {
        do {
            try service.unregister()
            lastErrorMessage = nil
        } catch {
            logger.error("Failed to disable sync agent: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
        refresh()
    }

    func set(enabled: Bool) {
        enabled ? enable() : disable()
    }

    /// Human-readable status for the settings pane.
    var statusDescription: String {
        switch status {
        case .notRegistered: return "Not running"
        case .enabled:       return "Running"
        case .requiresApproval: return "Needs approval in System Settings › Login Items"
        case .notFound:      return "Not installed"
        @unknown default:    return "Unknown"
        }
    }
}
