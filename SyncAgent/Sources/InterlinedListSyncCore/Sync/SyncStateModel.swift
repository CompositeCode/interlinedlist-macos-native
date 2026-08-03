import Foundation
import SwiftUI

/// Observable, main-actor projection of the engine's state for the menu bar and
/// preferences UI. The `AppDelegate` feeds it from the engine's event stream.
@MainActor
public final class SyncStateModel: ObservableObject {

    @Published public var status: SyncStatus = .idle
    @Published public var lastSyncedAt: Date?
    @Published public var lastError: String?
    @Published public var lastSummary: SyncSummary?
    @Published public var accountEmail: String?

    public init() {}

    public func apply(_ event: SyncEvent) {
        switch event {
        case .statusChanged(let status):
            self.status = status
            if case .error(let message) = status { lastError = message }
            else if status != .offline { lastError = nil }
        case .cycleCompleted(let summary):
            lastSummary = summary
            lastSyncedAt = summary.finishedAt
        case .conflictCreated:
            break
        case .authRequired:
            break
        }
    }

    // MARK: - Presentation

    public var statusTitle: String {
        switch status {
        case .idle:        return lastSyncedAt == nil ? "Idle" : "Up to date"
        case .syncing:     return "Syncing…"
        case .paused:      return "Paused"
        case .offline:     return "Offline"
        case .signedOut:   return "Signed out"
        case .authExpired: return "Sign-in required"
        case .error:       return "Error"
        }
    }

    public var lastSyncedTitle: String {
        guard let lastSyncedAt else { return "Last synced: Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last synced: \(formatter.localizedString(for: lastSyncedAt, relativeTo: Date()))"
    }

    /// SF Symbol name reflecting current status, for the menu-bar icon.
    public var symbolName: String {
        switch status {
        case .idle:        return "arrow.triangle.2.circlepath"
        case .syncing:     return "arrow.triangle.2.circlepath.circle.fill"
        case .paused:      return "pause.circle"
        case .offline:     return "wifi.slash"
        case .signedOut,
             .authExpired: return "person.crop.circle.badge.exclamationmark"
        case .error:       return "exclamationmark.triangle.fill"
        }
    }
}
