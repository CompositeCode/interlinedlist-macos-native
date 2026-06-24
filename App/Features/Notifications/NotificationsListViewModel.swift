// NotificationsListViewModel
//
// Drives `NotificationsRootView`: the M5 notifications tray (PLAN.md
// §1 "Notifications", §6 M5). Owns the rendered tray, the unread
// count, and the loading / error state. Reads through
// `NotificationsServicing` only — no direct API access — so unit
// tests substitute a stub service.
//
// Optimistic UI per the swift-engineer skill on `markRead(id:)`:
// snapshot the row's prior `isRead`, flip it locally, call the
// service, and on failure restore the snapshot. The bus is notified
// on success so peer surfaces (the dock-badge coordinator, any other
// tray view) update without polling.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class NotificationsListViewModel {

    // MARK: - Dependencies

    private let service: NotificationsServicing
    private let bus: NotificationsEventBus?

    // MARK: - Observable state

    /// The rendered tray rows, newest-first as the server returns them.
    private(set) var items: [InterlinedDomain.Notification] = []

    /// Server-authoritative unread count (`NotificationTray.unreadCount`).
    /// Drives the dock-badge label and any sidebar pip.
    private(set) var unreadCount: Int = 0

    /// True while a tray load is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load / mark-read.
    /// Cleared on the next successful round-trip.
    private(set) var error: Error?

    /// True once the first tray load has resolved (success or failure).
    /// Used by the view to distinguish "first render shimmer" from
    /// "loaded with an empty tray".
    private(set) var hasLoadedOnce: Bool = false

    /// Per-notification debounce set so rapid tap-to-mark-read on the
    /// same row doesn't double-fire the service call.
    private var pendingMarkReadOperations: Set<String> = []

    // MARK: - Init

    init(
        service: NotificationsServicing,
        notificationsEventBus: NotificationsEventBus? = nil
    ) {
        self.service = service
        self.bus = notificationsEventBus
    }

    // MARK: - Intents

    /// First-time + pull-to-refresh load. Replaces the rendered tray
    /// with the server payload and posts a `trayRefreshed` event so
    /// the dock-badge coordinator updates the unread count.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let tray = try await service.tray()
            items = tray.items
            unreadCount = tray.unreadCount
            error = nil
            hasLoadedOnce = true
            bus?.post(.trayRefreshed(unreadCount: tray.unreadCount))
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
    }

    /// Marks one row read. Optimistic: flip locally, call the service,
    /// roll back on failure. Idempotent — calling on an already-read
    /// row is a no-op (no service call). Bound to row taps and to a
    /// context-menu "Mark as read".
    func markRead(id: String) async {
        guard !pendingMarkReadOperations.contains(id) else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = items[index]
        guard !snapshot.isRead else { return }
        pendingMarkReadOperations.insert(id)
        defer { pendingMarkReadOperations.remove(id) }
        // Optimistic flip.
        items[index] = InterlinedDomain.Notification(
            id: snapshot.id,
            kind: snapshot.kind,
            actor: snapshot.actor,
            target: snapshot.target,
            createdAt: snapshot.createdAt,
            isRead: true,
            readAt: Date(),
            title: snapshot.title,
            body: snapshot.body
        )
        let priorUnread = unreadCount
        unreadCount = max(0, unreadCount - 1)
        do {
            try await service.markRead(id: id)
            error = nil
            bus?.post(.markedRead(id: id))
        } catch {
            // Rollback.
            items[index] = snapshot
            unreadCount = priorUnread
            self.error = error
        }
    }

    /// Marks every row read in one call. Optimistic: every row flips
    /// locally and `unreadCount` drops to zero; on failure the
    /// snapshot is restored. Bound to the menu command + a toolbar
    /// affordance.
    func markAllRead() async {
        let snapshot = items
        let priorUnread = unreadCount
        let now = Date()
        items = items.map { notification in
            guard !notification.isRead else { return notification }
            return InterlinedDomain.Notification(
                id: notification.id,
                kind: notification.kind,
                actor: notification.actor,
                target: notification.target,
                createdAt: notification.createdAt,
                isRead: true,
                readAt: now,
                title: notification.title,
                body: notification.body
            )
        }
        unreadCount = 0
        do {
            try await service.markAllRead()
            error = nil
            bus?.post(.markedAllRead)
        } catch {
            items = snapshot
            unreadCount = priorUnread
            self.error = error
        }
    }

    /// Convenience for tests + previews — seed the rendered tray
    /// without going through the service.
    func seedForTest(items: [InterlinedDomain.Notification], unreadCount: Int) {
        self.items = items
        self.unreadCount = unreadCount
        self.hasLoadedOnce = true
    }
}
