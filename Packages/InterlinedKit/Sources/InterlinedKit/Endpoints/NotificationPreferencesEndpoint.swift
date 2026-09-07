import Foundation

/// Request builders for **notification preferences** (work-consolidation.md G18)
/// — the Settings ▸ Notifications pane.
///
/// The read returns a typed event catalogue with server-driven labels and
/// descriptions, so the pane is data-driven: new event types appear without a
/// client release. The per-event `channels.push` flags are the switchboard
/// G9 push will consume.
public enum NotificationPreferences {

    /// `GET /api/user/notification-preferences` — the event catalogue.
    public static func get() -> Request<NotificationPreferencesResponse> {
        Request(method: .get, path: "/api/user/notification-preferences", auth: .bearer)
    }

    /// `PATCH /api/user/notification-preferences` — write changed channels.
    ///
    /// Returns the updated catalogue so the caller can re-render from the
    /// server's authoritative copy rather than trusting its local edit.
    public static func update(
        _ body: UpdateNotificationPreferencesRequest
    ) -> Request<NotificationPreferencesResponse> {
        Request(
            method: .patch,
            path: "/api/user/notification-preferences",
            body: .json(body),
            auth: .bearer
        )
    }
}
