// NotificationsEventBus
//
// Cross-window pub/sub bus for the M5 Notifications + Social Requests
// features (PLAN.md §6 M5). Mirrors `ComposerEventBus` and
// `ListsEventBus`: an internal actor holds the live continuations
// keyed by UUID; `events()` returns an `AsyncStream<NotificationsEvent>`
// per subscriber.
//
// The bus exists so the dock-badge coordinator, the tray view, and the
// requests-panel rows can all react in place to writes performed by
// other windows / menu commands without forcing a full refetch (a
// `markAllRead` from the menu shouldn't make the tray view repaint via
// re-fetch — it should mutate the rendered list).
//
// Decision 0003 compliance: this file consumes only `InterlinedDomain`;
// no kit symbol crosses this boundary.

import Foundation
import InterlinedDomain

/// One event a M5 Notifications or Social Requests view emits after
/// a successful write. Subscribers translate these into pure local
/// mutations or trigger a re-read of the tray when the unread count
/// is the load-bearing data (e.g. dock-badge coordinator).
enum NotificationsEvent: Sendable, Equatable {

    /// The tray was reloaded from the server. Used by the dock-badge
    /// coordinator to write the unread count without polling.
    case trayRefreshed(unreadCount: Int)

    /// A single notification was marked read. Other tray views patch
    /// the matching row in place and decrement their unread count.
    case markedRead(id: String)

    /// All notifications were marked read. Other tray views set every
    /// row's `isRead` to `true` and zero their unread count.
    case markedAllRead

    /// An inbound follow request was approved (rolled off the inbox).
    /// The requests panel and the tray's inline request rows drop the
    /// row matching `requestUserID`.
    case requestApproved(requestUserID: String)

    /// An inbound follow request was rejected (rolled off the inbox).
    case requestRejected(requestUserID: String)
}

/// Shared event bus for the M5 Notifications + Social Requests
/// features. Use `events()` for a subscription stream; terminate by
/// cancelling the consuming task.
final class NotificationsEventBus: Sendable {

    private let storage = Storage()

    init() {}

    /// Returns an `AsyncStream` that yields every event posted after
    /// subscription. The stream finishes when the consumer cancels.
    func events() -> AsyncStream<NotificationsEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.storage.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.storage.unregister(id: id) }
            }
        }
    }

    /// Publish an event to every active subscriber. Late subscribers
    /// do not receive past events.
    func post(_ event: NotificationsEvent) {
        Task { await storage.broadcast(event) }
    }

    // MARK: - Storage

    /// Holds the live continuations keyed by registration UUID. An
    /// actor because publishers and subscribers aren't serialized.
    private actor Storage {
        private var continuations: [UUID: AsyncStream<NotificationsEvent>.Continuation] = [:]

        func register(id: UUID, continuation: AsyncStream<NotificationsEvent>.Continuation) {
            continuations[id] = continuation
        }

        func unregister(id: UUID) {
            continuations[id] = nil
        }

        func broadcast(_ event: NotificationsEvent) {
            for continuation in continuations.values {
                continuation.yield(event)
            }
        }
    }
}
