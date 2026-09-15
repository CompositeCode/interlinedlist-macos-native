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
/// rather than `Paginated<T>`.
public enum Notifications {

    /// `GET /api/notifications` — the tray, read **and** unread.
    ///
    /// The scope defaults to **`all`**, not `tray`. VERIFIED live 2026-09-15
    /// (GitHub #80) on the test account:
    ///
    /// ```
    /// ?scope=tray            → 1 item   (the single unread one), `limit` ignored
    /// ?scope=tray&limit=5    → 1 item   (still just the unread one)
    /// ?scope=all&limit=3     → 3 items  (read and unread, newest first)
    /// ?scope=all&limit=10    → 10 items
    /// ?scope=all             → 20 items (the account's `notificationTrayLimit`)
    /// ```
    ///
    /// `scope=tray` is **unread-only** and ignores `limit`, so on macOS the tray
    /// emptied as you read it while the web bell retained recent history. Same
    /// feature, different behaviour — and the macOS one was the surprising one.
    ///
    /// `scope=all` is what the web bell uses: the last N regardless of read
    /// state, honouring `limit`, and falling back to the account preference when
    /// it is absent. `unreadCount` is returned under both scopes, so the badge
    /// still comes from the same call.
    public static func tray(scope: String = "all", limit: Int? = nil) -> Request<NotificationTrayDTO> {
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
