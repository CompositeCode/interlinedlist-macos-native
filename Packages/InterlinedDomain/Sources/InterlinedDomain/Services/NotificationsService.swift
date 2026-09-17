import Foundation
import InterlinedKit

// MARK: - NotificationsServicing

/// The notifications surface the App layer codes against — tray read,
/// mark-one-read, mark-all-read (PLAN.md §1 "Notifications", §6 M5).
///
/// **Scope.** The API only accepts `scope=tray` today (the kit endpoint
/// encodes it for us). The user-side `notificationTrayLimit` (10–40, default
/// 20) controls the page size.
///
/// **Scope — corrected 2026-09-15 (GitHub #80).** The tray reads `scope=all`,
/// not `scope=tray`.
///
/// `scope=tray` returns **unread rows only** and ignores `limit`, so the macOS
/// tray emptied as the user read it while the web bell retained recent history.
/// A glanced-at notification simply vanished, with no way back to it. `scope=all`
/// is what the web bell uses — the last N regardless of read state — and it
/// honours `limit`, falling back to the account's stored `notificationTrayLimit`
/// when the parameter is absent. Probed live:
///
/// ```
/// ?scope=tray&limit=5  → 1 item   (the single unread one)
/// ?scope=all&limit=3   → 3 items
/// ?scope=all&limit=10  → 10 items
/// ?scope=all           → 20 items (the stored preference)
/// ```
///
/// `unreadCount` is returned under both scopes, so the badge is unaffected.
///
/// The client-side `prefix` that used to cap the rows is gone with it: it existed
/// only because `scope=tray` ignored the parameter, and it made the preference
/// *appear* to work while the rows being trimmed were the wrong rows.
///
/// Follows the same DI shape as the other domain services — takes its
/// `APIClientProtocol` as a parameter so unit tests run against a stub.
public protocol NotificationsServicing: Sendable {

    /// Loads the current notification tray, showing at most `limit` rows.
    /// Returns the domain `NotificationTray` (server-authoritative
    /// `unreadCount` + the items page).
    ///
    /// - Parameter limit: the account's `notificationTrayLimit`. `nil` (the
    ///   default, via the `tray()` convenience) lets the server apply the stored
    ///   preference itself. `unreadCount` is always the server's own total and
    ///   stays authoritative for the badge regardless of how many rows come
    ///   back — a limit that shrinks the list must not shrink the badge.
    func tray(limit: Int?) async throws -> NotificationTray

    /// Marks a single notification read by id. The service does not return
    /// the updated row — the wire response is a `{ ok: Bool }` confirmation.
    /// Callers update their local copy optimistically.
    func markRead(id: String) async throws

    /// Marks every notification read at once. The wire response carries
    /// `{ ok: Bool, updated: Int }` — the count is dropped here because
    /// no caller has needed it; the App layer reloads the tray after the
    /// call to refresh `unreadCount`.
    func markAllRead() async throws
}

public extension NotificationsServicing {

    /// Loads the tray with no client-side limit — the server applies the
    /// account's own `notificationTrayLimit`. Kept so callers that have no
    /// preference to hand (background refreshers, tests) read unchanged.
    func tray() async throws -> NotificationTray {
        try await tray(limit: nil)
    }
}

// MARK: - NotificationsService

public final class NotificationsService: NotificationsServicing {

    private let api: APIClientProtocol

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func tray(limit: Int?) async throws -> NotificationTray {
        // `scope=all` honours `limit` server-side, so the client-side `prefix`
        // that used to sit here is gone (GitHub #80). That trim existed because
        // `scope=tray` ignored the parameter — it made `notificationTrayLimit`
        // *appear* to work while the rows being trimmed were unread-only, so the
        // preference could only ever shrink an already-wrong list.
        //
        // Deliberately not re-added as a belt-and-braces cap: a client-side trim
        // over a correctly-limited response is invisible when it agrees with the
        // server and wrong when it does not.
        let dto = try await api.send(Notifications.tray(limit: limit))
        return NotificationTray(from: dto)
    }

    public func markRead(id: String) async throws {
        _ = try await api.send(Notifications.markRead(id: id))
    }

    public func markAllRead() async throws {
        _ = try await api.send(Notifications.markAllRead())
    }
}
