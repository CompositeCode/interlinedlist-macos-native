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
/// **Tray limit — corrected 2026-09-09 (G35 / issue #43).** The previous note
/// here claimed the server ignores a client `limit` outright. A live probe
/// disproves that: unscoped, `?limit=5` returns 5 rows and `?limit=40` returns
/// 36, and omitting it returns exactly the account's stored limit. Only the
/// `scope=tray` form ignores it. So `tray(limit:)` both sends the value *and*
/// caps the decoded rows client-side — the send is what will start working the
/// moment the tray route honours it, and the cap is what makes the preference
/// observable today.
///
/// Follows the same DI shape as the other domain services — takes its
/// `APIClientProtocol` as a parameter so unit tests run against a stub.
public protocol NotificationsServicing: Sendable {

    /// Loads the current notification tray, showing at most `limit` rows.
    /// Returns the domain `NotificationTray` (server-authoritative
    /// `unreadCount` + the items page).
    ///
    /// - Parameter limit: the account's `notificationTrayLimit`. `nil` (the
    ///   default, via the `tray()` convenience) leaves the page size entirely
    ///   to the server. `unreadCount` is never capped — it is the server's own
    ///   total and stays authoritative for the badge even when the rendered
    ///   rows are trimmed.
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
        let dto = try await api.send(Notifications.tray(limit: limit))
        let tray = NotificationTray(from: dto)
        // Client-side cap: `scope=tray` ignores the query parameter today, so
        // without this the user's limit would have no visible effect. The
        // server-authoritative `unreadCount` is preserved as-is — trimming the
        // rendered rows must not understate the badge.
        guard let limit, limit > 0, tray.items.count > limit else { return tray }
        return NotificationTray(
            unreadCount: tray.unreadCount,
            items: Array(tray.items.prefix(limit))
        )
    }

    public func markRead(id: String) async throws {
        _ = try await api.send(Notifications.markRead(id: id))
    }

    public func markAllRead() async throws {
        _ = try await api.send(Notifications.markAllRead())
    }
}
