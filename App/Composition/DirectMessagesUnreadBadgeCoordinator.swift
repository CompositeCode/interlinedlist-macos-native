// DirectMessagesUnreadBadgeCoordinator
//
// Owns the dock-badge subscription glue for the Direct Messages feature
// (the-gaps.md G1). Mirrors `NotificationsUnreadBadgeCoordinator`: it
// listens on `DirectMessagesEventBus` and translates each event into the
// DM contribution to the shared dock badge.
//
// Unlike the notifications coordinator (which predates the aggregator and
// still writes a raw count through its own closure), this coordinator was
// born after `UnreadBadgeAggregator` existed, so it reports into the
// `.directMessages` slot of the aggregator via the injected closure. The
// aggregator sums the DM and notifications slots and performs the single
// actual badge write. This keeps DMs from clobbering the notifications
// contribution and vice-versa.
//
// The DM list view model posts `unreadCountChanged(...)` after every
// `unreadCount()` read and after a thread is opened / read; the
// coordinator translates those into the current DM unread total.
//
// Decision 0003 compliance: lives in `App/Composition/` and imports only
// `Foundation` and `InterlinedDomain`; the AppKit reach is hidden behind
// the `@MainActor` closure the composition root supplies.

import Foundation
import InterlinedDomain

/// Drives the DM contribution of the dock-tile badge from
/// `DirectMessagesEventBus` events. Minimal by design — every business
/// rule lives in the DM view models; the coordinator only folds events
/// into a count and reports it upward.
final class DirectMessagesUnreadBadgeCoordinator: @unchecked Sendable {

    /// Reports the DM unread count into the shared badge aggregator.
    /// Injected so tests record without AppKit.
    private let reportCount: @MainActor @Sendable (Int) -> Void

    /// The event bus the coordinator subscribes to.
    private let bus: DirectMessagesEventBus

    /// Best-effort tracker of the last authoritative DM unread count so a
    /// `threadRead` event can decrement without a fresh `unreadCount()`
    /// round-trip. `nil` until the first `unreadCountChanged` arrives.
    private var lastKnownUnread: Int?

    /// Subscription task; `nil` until `start()` is called.
    private var subscription: Task<Void, Never>?

    init(
        bus: DirectMessagesEventBus,
        reportCount: @escaping @MainActor @Sendable (Int) -> Void
    ) {
        self.bus = bus
        self.reportCount = reportCount
    }

    /// Begins consuming the event stream. Safe to call multiple times —
    /// re-subscribing replaces the prior task.
    func start() {
        subscription?.cancel()
        let stream = bus.events()
        let reportCount = self.reportCount
        subscription = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                let count = await self.fold(event: event)
                await MainActor.run { reportCount(count) }
            }
        }
    }

    /// Stops consuming events. Idempotent.
    func stop() {
        subscription?.cancel()
        subscription = nil
    }

    /// Visible for tests — fold an event into the next DM unread count.
    /// Returns the value the coordinator would have reported for `event`.
    /// Pure: no AppKit, no I/O.
    func fold(event: DirectMessagesEvent) async -> Int {
        switch event {
        case .unreadCountChanged(let count):
            let clamped = max(0, count)
            lastKnownUnread = clamped
            return clamped
        case .threadRead:
            // Opening a thread clears that conversation's unread inbound
            // messages; without a per-conversation count we conservatively
            // leave the known total in place and let the next
            // `unreadCountChanged` (posted right after mark-read) supply
            // the authoritative value. Reporting the last-known avoids a
            // flicker to a wrong number.
            return lastKnownUnread ?? 0
        case .messageSent:
            // Sending a message never changes *your own* unread count.
            return lastKnownUnread ?? 0
        }
    }
}
