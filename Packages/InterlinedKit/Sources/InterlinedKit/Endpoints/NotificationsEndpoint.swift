import Foundation

/// Request builders for the **Notifications** API group — the notification
/// tray, mark-one-read, and mark-all-read.
///
/// Follows the `Request.swift` conventions: one `public enum` namespace,
/// factories returning `Request<DTO>`, explicit `AuthRequirement`, path-only
/// URLs, nil-skipping query items, and never throwing.
///
/// Auth: all `.bearer` (decision 0001 — Bearer works on the notifications
/// surface despite the docs marking it session-only).
///
/// `GET /api/notifications` does **not** use the standard
/// `{ data, pagination }` envelope; it returns
/// `{ unreadCount, items: [...] }`, so it decodes into `NotificationTrayDTO`
/// rather than `Paginated<T>`. The `scope=tray` query parameter is required by
/// the API and defaulted here.
public enum Notifications {

    /// `GET /api/notifications` (with `scope=tray`).
    ///
    /// `limit` is optional and omitted by default. VERIFIED live 2026-09-09
    /// (G35 / issue #43): the route honours `limit` in its *unscoped* form
    /// (`?limit=5` → 5 rows, `?limit=40` → 36 rows on the test account) and
    /// falls back to the account's `notificationTrayLimit` when absent
    /// (no params → exactly 20 rows, matching the stored preference). Under
    /// `scope=tray` the server currently ignores `limit` and returns unread
    /// rows only, so the preference is *also* enforced client-side by
    /// `NotificationsService.tray(limit:)` — see the note there.
    public static func tray(scope: String = "tray", limit: Int? = nil) -> Request<NotificationTrayDTO> {
        Request(
            method: .get,
            path: "/api/notifications",
            query: [
                .string("scope", scope),
                .int("limit", limit)
            ],
            auth: .bearer
        )
    }

    /// `PATCH /api/notifications/[id]/read`
    public static func markRead(id: String) -> Request<NotificationReadResponse> {
        Request(method: .patch, path: "/api/notifications/\(id)/read", auth: .bearer)
    }

    /// `POST /api/notifications/mark-all-read`
    public static func markAllRead() -> Request<NotificationMarkAllReadResponse> {
        Request(method: .post, path: "/api/notifications/mark-all-read", auth: .bearer)
    }

    /// `DELETE /api/notifications/[id]` — remove a single notification from the
    /// tray (work-consolidation.md G27). The client could previously only mark
    /// one read.
    ///
    /// VERIFIED live 2026-09-06: `OPTIONS` reports `Allow: DELETE, OPTIONS` and
    /// a real `DELETE` returned **204 No Content** — so there is no body to
    /// decode. Send with `sendVoid`.
    public static func delete(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/notifications/\(id)", auth: .bearer)
    }
}
