// NotificationsUnreadBadgeCoordinator
//
// Owns the dock-badge subscription glue for the M5 Notifications
// feature (PLAN.md §5 — "dock badge for unread", §6 M5). The
// coordinator listens on `NotificationsEventBus` for tray-refresh /
// mark-read / mark-all-read events and writes the unread count to the
// `AppDelegate` (the one allowed AppKit-importing file).
//
// The tray view model is responsible for posting `trayRefreshed(...)`
// after every successful `NotificationsService.tray()` round-trip;
// `markedRead(...)` and `markedAllRead` are posted from their
// respective entry points. The coordinator translates each event into
// a `dock-tile badge label` write.
//
// Decision 0003 compliance: this file lives in `App/Composition/`
// (which Decision 0003 allows to cross every layer boundary). It
// imports only `Foundation` and `InterlinedDomain` at the type level
// — the AppKit dependency is hidden behind a `@MainActor` closure the
// composition root provides, so the test composition can substitute
// a recording closure without touching AppKit.

import Foundation
import InterlinedDomain

/// Drives the macOS dock-tile badge from `NotificationsEventBus`
/// events. The coordinator is intentionally minimal — every business
/// rule (when to fetch, what counts as unread) lives in the tray
/// view model. The coordinator only translates events to badge writes.
final class NotificationsUnreadBadgeCoordinator: @unchecked Sendable {

    /// The dock-badge writer, injected so tests record without AppKit.
    /// Lives on the main actor because the underlying `NSApp.dockTile`
    /// API requires it.
    private let writeBadge: @MainActor @Sendable (Int) -> Void

    /// The event bus the coordinator subscribes to.
    private let bus: NotificationsEventBus

    /// Best-effort tracker of the last unread count so `markedRead` /
    /// `markedAllRead` events can update the badge without a tray
    /// refetch. `nil` until the first `trayRefreshed` event arrives.
    private var lastKnownUnread: Int?

    /// Subscription task; `nil` until `start()` is called.
    private var subscription: Task<Void, Never>?

    init(
        bus: NotificationsEventBus,
        writeBadge: @escaping @MainActor @Sendable (Int) -> Void
    ) {
        self.bus = bus
        self.writeBadge = writeBadge
    }

    /// Begins consuming the event stream. Safe to call multiple times
    /// — re-subscribing replaces the prior task.
    func start() {
        subscription?.cancel()
        let stream = bus.events()
        let writeBadge = self.writeBadge
        subscription = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                let count = await self.fold(event: event)
                await MainActor.run { writeBadge(count) }
            }
        }
    }

    /// Stops consuming events. Idempotent.
    func stop() {
        subscription?.cancel()
        subscription = nil
    }

    /// Visible for tests — fold an event into the next unread count.
    /// Returns the value the coordinator would have written to the
    /// badge for `event`. Pure: no AppKit, no I/O.
    func fold(event: NotificationsEvent) async -> Int {
        switch event {
        case .trayRefreshed(let unreadCount):
            lastKnownUnread = unreadCount
            return unreadCount
        case .markedRead:
            let next = max(0, (lastKnownUnread ?? 0) - 1)
            lastKnownUnread = next
            return next
        case .markedAllRead:
            lastKnownUnread = 0
            return 0
        case .requestApproved, .requestRejected:
            // Inbound-request actions don't change the unread count by
            // themselves; the tray re-fetch that follows will post a
            // `trayRefreshed` with the authoritative value.
            return lastKnownUnread ?? 0
        }
    }
}
