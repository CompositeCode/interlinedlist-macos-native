import Foundation
import InterlinedKit

// MARK: - NotificationsServicing

/// The notifications surface the App layer codes against — tray read,
/// mark-one-read, mark-all-read (PLAN.md §1 "Notifications", §6 M5).
///
/// **Scope.** The API only accepts `scope=tray` today (the kit endpoint
/// encodes it for us). The user-side `notificationTrayLimit` (server-side,
/// clamped 10–40, default 20) controls the page size; this service does
/// **not** pass a client-side `limit` because the server ignores it.
///
/// Follows the same DI shape as the other domain services — takes its
/// `APIClientProtocol` as a parameter so unit tests run against a stub.
public protocol NotificationsServicing: Sendable {

    /// Loads the current notification tray. Returns the domain
    /// `NotificationTray` (server-authoritative `unreadCount` + the items
    /// page).
    func tray() async throws -> NotificationTray

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

// MARK: - NotificationsService

public final class NotificationsService: NotificationsServicing {

    private let api: APIClientProtocol

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func tray() async throws -> NotificationTray {
        let dto = try await api.send(Notifications.tray())
        return NotificationTray(from: dto)
    }

    public func markRead(id: String) async throws {
        _ = try await api.send(Notifications.markRead(id: id))
    }

    public func markAllRead() async throws {
        _ = try await api.send(Notifications.markAllRead())
    }
}
