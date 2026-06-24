// NotificationsPermissionCoordinator
//
// Wraps the lazy UNUserNotifications permission request (PLAN.md §5
// "system notifications", §6 M5). Per macOS HIG we ask only when the
// user shows intent — the first visit to the Notifications tray view.
// The "have we asked" flag persists in `UserDefaults` so re-launches
// don't re-prompt; that single boolean does not merit a SwiftData
// schema.
//
// The coordinator owns no AppKit dependencies — it talks to
// `UNUserNotificationCenter` directly, which is a Foundation /
// UserNotifications API that is allowed in SwiftUI files. The
// Decision 0005 AppKit grep gate is unaffected.
//
// Per decision 0003, this file imports no Kit symbols.

import Foundation
import UserNotifications

/// One-shot permission requester. Constructed by the
/// `NotificationsRootView` on its first `.task`; the coordinator
/// records its "have we asked" flag in `UserDefaults` so subsequent
/// visits do not re-prompt.
@MainActor
final class NotificationsPermissionCoordinator {

    /// Key for the "have we asked once" boolean. Stable across
    /// installs so a re-launch sees the prior decision.
    static let askedKey = "InterlinedList.notifications.permissionAsked"

    /// The center to talk to. Held as a protocol so unit tests
    /// substitute a stub without booting the real notification
    /// machinery.
    private let center: NotificationsAuthorizationRequesting
    private let defaults: UserDefaults

    init(
        center: NotificationsAuthorizationRequesting = UNUserNotificationCenter.current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
    }

    /// True if `requestIfNeeded` has already run at least once on this
    /// machine. Used by tests; the view does not need to read it.
    var hasAsked: Bool {
        defaults.bool(forKey: Self.askedKey)
    }

    /// Requests notification permission iff this is the first visit.
    /// Idempotent — repeated calls after the first one are no-ops, so
    /// the view can call it inside `.task` without guarding.
    ///
    /// - Returns: `true` when the system granted permission (whether
    ///   this call did the asking or a prior call did). `false` when
    ///   permission was denied or the request failed.
    @discardableResult
    func requestIfNeeded() async -> Bool {
        guard !hasAsked else {
            // Already asked once — return whatever the current
            // settings say so callers can adjust UI accordingly.
            return await currentlyAuthorized()
        }
        defaults.set(true, forKey: Self.askedKey)
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // The request itself failed (rare — usually only happens
            // when the system service is unavailable). Treat as
            // denied; the caller renders the fallback chrome.
            return false
        }
    }

    /// Reads the current authorization state without prompting. Used
    /// when the "have we asked" flag is already set so the view knows
    /// whether to surface a "system notifications are off" hint.
    func currentlyAuthorized() async -> Bool {
        await center.currentAuthorizationSettings().isAuthorized
    }
}

// MARK: - Protocol seam (tests substitute this)

/// The narrow surface `NotificationsPermissionCoordinator` actually
/// uses on `UNUserNotificationCenter`. A protocol so the coordinator
/// is unit-testable without a real notification system.
protocol NotificationsAuthorizationRequesting: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func currentAuthorizationSettings() async -> NotificationsAuthorizationSettings
}

/// The narrow projection of `UNNotificationSettings` the coordinator
/// reads. Lets tests build a synthetic settings value without faking
/// the entire system class.
struct NotificationsAuthorizationSettings: Sendable {
    let isAuthorized: Bool
}

extension UNUserNotificationCenter: NotificationsAuthorizationRequesting {
    func currentAuthorizationSettings() async -> NotificationsAuthorizationSettings {
        let settings: UNNotificationSettings = await notificationSettings()
        // macOS UN authorization has `.authorized` and `.provisional`
        // (and `.notDetermined` / `.denied`); `.ephemeral` is
        // iOS-only and unavailable on macOS.
        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        return NotificationsAuthorizationSettings(isAuthorized: authorized)
    }
}
