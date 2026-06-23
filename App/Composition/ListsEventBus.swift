// ListsEventBus
//
// Cross-window publish/subscribe bus for the M3 Lists feature
// (PLAN.md §6 M3). Mirrors `ComposerEventBus`: an internal actor
// holds the live continuations keyed by UUID, and `events()` returns
// an `AsyncStream<ListsEvent>` per subscriber.
//
// Wave 3 proved the pattern: lists / detail / row / sharing / graph
// views that need to react to other windows' writes subscribe to the
// bus, then translate each event into a pure local mutation (no
// refetch). Sidebar listings, schema editors, rows tables, watchers,
// and the connections graph all subscribe so a write in any open
// window propagates everywhere.
//
// Decision 0003 compliance: this file consumes only `InterlinedDomain`;
// no kit symbol crosses this boundary.

import Foundation
import InterlinedDomain

/// One event a M3 Lists view emits after a successful write. Subscribers
/// translate these into pure local mutations.
enum ListsEvent: Sendable, Equatable {

    /// A brand-new list was created. The owned-lists sidebar prepends it.
    case listCreated(OwnedList)

    /// An existing list was updated (rename, description, parent, visibility,
    /// or a fresh GitHub refresh). Subscribers swap the cached copy in place.
    case listUpdated(OwnedList)

    /// A list was deleted. Open views remove the corresponding row.
    case listDeleted(id: String)

    /// A new row was added to `listId`. The rows table appends.
    case rowCreated(listId: String, row: ListRow)

    /// A row was edited. The rows table swaps in place.
    case rowUpdated(listId: String, row: ListRow)

    /// A row was deleted. The rows table removes it.
    case rowDeleted(listId: String, rowId: String)

    /// A list's schema was rewritten. Any open rows table reloads its
    /// schema (and therefore its columns).
    case schemaChanged(listId: String, schema: ListSchema)

    /// A watcher's role on `listId` changed. The watchers panel swaps in
    /// place.
    case watcherChanged(listId: String, watcher: ListWatcher)

    /// A watcher was removed from `listId`.
    case watcherRemoved(listId: String, userId: String)

    /// A connection was created. The graph view appends.
    case connectionAdded(ListConnection)

    /// A connection was removed. The graph view drops it.
    case connectionRemoved(id: String)
}

/// Shared event bus for the M3 Lists feature. Use `events()` for a
/// subscription stream; terminate by cancelling the consuming task.
final class ListsEventBus: Sendable {

    private let storage = Storage()

    init() {}

    /// Returns an `AsyncStream` that yields every event posted after
    /// subscription. The stream finishes when the consumer cancels.
    func events() -> AsyncStream<ListsEvent> {
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
    func post(_ event: ListsEvent) {
        Task { await storage.broadcast(event) }
    }

    // MARK: - Storage

    /// Holds the live continuations keyed by registration UUID. An
    /// actor because publishers and subscribers aren't serialized.
    private actor Storage {
        private var continuations: [UUID: AsyncStream<ListsEvent>.Continuation] = [:]

        func register(id: UUID, continuation: AsyncStream<ListsEvent>.Continuation) {
            continuations[id] = continuation
        }

        func unregister(id: UUID) {
            continuations[id] = nil
        }

        func broadcast(_ event: ListsEvent) {
            for continuation in continuations.values {
                continuation.yield(event)
            }
        }
    }
}
