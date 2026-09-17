// EventBusStorage
//
// The shared subscriber registry behind the four feature event buses
// (`ListsEventBus`, `ComposerEventBus`, `NotificationsEventBus`,
// `DirectMessagesEventBus`). Each of those was carrying its own private copy of
// the same actor; this is that copy, written once and made synchronous.
//
// Why synchronous registration matters (GitHub #82). The previous actor-backed
// version registered the continuation *inside a `Task`*:
//
//     return AsyncStream { continuation in
//         Task { await self.storage.register(id: id, continuation: continuation) }
//     }
//
// so `events()` returned a stream that was not yet in the subscriber table. A
// caller that subscribed and then immediately performed a write could miss its
// own event, and no number of `Task.yield()`s closed the window — registration
// was waiting on actor scheduling, not on cooperative yields. The tests papered
// over it with a fixed 10 ms sleep ("give the subscription a beat to register"),
// which is exactly the pattern that passes on an idle machine and loses the race
// when the suite competes with a cold build. In the running app the same window
// showed up as an unread badge that occasionally did not move.
//
// Registering under a lock inside the `AsyncStream` build closure — which
// `AsyncStream` invokes synchronously during init — closes it: by the time
// `events()` returns, the subscriber is live.
//
// `Mutex` rather than an actor because every operation here is a short,
// non-suspending dictionary mutation and `yield` never blocks (`AsyncStream`'s
// default buffering policy is unbounded). An actor buys serialization this does
// not need and costs the synchrony this does.
//
// Per Decision 0003 this file lives in `App/Composition/` and imports no kit.

import Foundation
import Synchronization

final class EventBusStorage<Event: Sendable>: Sendable {

    private let continuations = Mutex<[UUID: AsyncStream<Event>.Continuation]>([:])

    init() {}

    /// A stream that is **already registered** by the time it is returned.
    ///
    /// The stream finishes when the consuming task is cancelled; termination
    /// unregisters the continuation so a dropped subscriber does not leak.
    func stream() -> AsyncStream<Event> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations.withLock { $0[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.continuations.withLock { $0[id] = nil }
            }
        }
    }

    /// Delivers `event` to every subscriber registered at the moment of the
    /// call. Late subscribers do not receive past events.
    ///
    /// The values are copied out under the lock and yielded outside it, so a
    /// subscriber that reacts by subscribing or unsubscribing cannot deadlock.
    func broadcast(_ event: Event) {
        let live = continuations.withLock { Array($0.values) }
        for continuation in live {
            continuation.yield(event)
        }
    }

    /// Live subscriber count. Exists so a test can assert that subscription
    /// happened without waiting on a clock.
    var subscriberCount: Int {
        continuations.withLock { $0.count }
    }
}
