import Foundation
import UserNotifications
import os

/// Thin wrapper over `UNUserNotificationCenter` for sync notifications.
@MainActor
public final class NotificationManager {

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "Notifications")

    public init() {}

    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error { logger.error("Notification auth error: \(error.localizedDescription, privacy: .public)") }
            else { logger.info("Notification auth granted: \(granted, privacy: .public)") }
        }
    }

    public func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    public func notifySyncCompleted(_ summary: SyncSummary) {
        guard summary.changeCount > 0 else { return }
        var parts: [String] = []
        if summary.pulled > 0 { parts.append("\(summary.pulled) updated") }
        if summary.pushed > 0 { parts.append("\(summary.pushed) uploaded") }
        if summary.created > 0 { parts.append("\(summary.created) created") }
        if summary.deletedLocal + summary.deletedRemote > 0 {
            parts.append("\(summary.deletedLocal + summary.deletedRemote) removed")
        }
        post(title: "Documents synced", body: parts.joined(separator: ", "))
    }

    public func notifyConflict(fileName: String) {
        post(title: "Sync conflict", body: "Your local edits were saved as \(fileName).")
    }

    public func notifyError(_ message: String) {
        post(title: "Sync error", body: message)
    }

    public func notifyAuthRequired() {
        post(title: "Sign in required", body: "Open InterlinedList and sign in to keep syncing.")
    }
}
