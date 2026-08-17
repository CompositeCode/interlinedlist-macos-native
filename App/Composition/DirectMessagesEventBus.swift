// DirectMessagesEventBus
//
// Cross-window pub/sub bus for the Direct Messages feature (work-consolidation.md
// G1). Mirrors `NotificationsEventBus` / `ComposerEventBus`: an internal
// actor holds the live continuations keyed by UUID; `events()` returns
// an `AsyncStream<DirectMessagesEvent>` per subscriber.
//
// The bus lets the DM list, an open thread, the composer sheet, and the
// unread-badge coordinator react in place to writes performed by other
// windows / menu commands without forcing a full refetch:
//   - sending a message updates the sender's conversation-list preview,
//   - reading a thread decrements the unread pip,
//   - a fresh `unreadCount()` read republishes the authoritative total.
//
// Decision 0003 compliance: this file lives in `App/Composition/` and
// consumes only `InterlinedDomain`; no kit symbol crosses the boundary.

import Foundation
import InterlinedDomain

/// One event a Direct Messages surface emits after a successful write /
/// read. Subscribers translate these into pure local mutations (a
/// conversation-list preview swap, an unread-pip decrement) or, for the
/// badge coordinator, into a dock-badge write.
enum DirectMessagesEvent: Sendable, Equatable {

    /// A fresh `unreadCount()` read landed. The badge aggregator writes
    /// this as the DM contribution to the dock badge; a sidebar pip binds
    /// to it too.
    case unreadCountChanged(Int)

    /// A message was sent to `recipientUsername`. Open list / thread
    /// surfaces for that conversation append it in place.
    case messageSent(recipientUsername: String, message: DirectMessage)

    /// A thread with `username` was opened and its inbound messages
    /// marked read. Peer surfaces drop that conversation's unread pip.
    case threadRead(username: String)
}

/// Shared event bus for the Direct Messages feature. Use `events()` for
/// a subscription stream; terminate by cancelling the consuming task.
final class DirectMessagesEventBus: Sendable {

    private let storage = Storage()

    init() {}

    /// Returns an `AsyncStream` that yields every event posted after
    /// subscription. The stream finishes when the consumer cancels.
    func events() -> AsyncStream<DirectMessagesEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.storage.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.storage.unregister(id: id) }
            }
        }
    }

    /// Publish an event to every active subscriber. Late subscribers do
    /// not receive past events.
    func post(_ event: DirectMessagesEvent) {
        Task { await storage.broadcast(event) }
    }

    // MARK: - Storage

    /// Holds the live continuations keyed by registration UUID. An actor
    /// because publishers and subscribers aren't serialized.
    private actor Storage {
        private var continuations: [UUID: AsyncStream<DirectMessagesEvent>.Continuation] = [:]

        func register(id: UUID, continuation: AsyncStream<DirectMessagesEvent>.Continuation) {
            continuations[id] = continuation
        }

        func unregister(id: UUID) {
            continuations[id] = nil
        }

        func broadcast(_ event: DirectMessagesEvent) {
            for continuation in continuations.values {
                continuation.yield(event)
            }
        }
    }
}
