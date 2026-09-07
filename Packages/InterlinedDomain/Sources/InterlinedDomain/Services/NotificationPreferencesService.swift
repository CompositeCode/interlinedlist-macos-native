import Foundation
import InterlinedKit

/// The notification-preferences surface the App layer codes against
/// (work-consolidation.md G18).
public protocol NotificationPreferencesServicing: Sendable {
    /// The server-driven event catalogue.
    func catalogue() async throws -> [NotificationEventPreference]
    /// Writes the given events' channels and returns the server's updated
    /// catalogue.
    func update(_ events: [NotificationEventPreference]) async throws -> [NotificationEventPreference]
}

/// Reads and writes `/api/user/notification-preferences`.
public final class NotificationPreferencesService: NotificationPreferencesServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func catalogue() async throws -> [NotificationEventPreference] {
        let response = try await api.send(NotificationPreferences.get())
        return response.events.map(NotificationEventPreference.init(from:))
    }

    public func update(
        _ events: [NotificationEventPreference]
    ) async throws -> [NotificationEventPreference] {
        // Only key + channels go back; labels and descriptions are server-owned.
        let body = UpdateNotificationPreferencesRequest(
            events: events.map { .init(key: $0.key, channels: $0.channels.dto) }
        )
        let response = try await api.send(NotificationPreferences.update(body))
        return response.events.map(NotificationEventPreference.init(from:))
    }
}
