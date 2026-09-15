// ComposerEventBus
//
// Cross-window publish/subscribe bus that lets the composer window
// notify open Timeline / Detail screens after a successful create /
// reply / update / delete, so they can prepend, replace, or remove the
// affected row without performing a full refetch (PLAN.md §6 M2 —
// "Closes on success and posts a notification … so the open Timeline
// can refresh").
//
// The bus is intentionally minimal: an `AsyncStream<Event>` per
// subscriber, fanned out by an internal actor that tracks each
// continuation by UUID. Built on top of an actor so the set of
// continuations is mutated safely under Swift 6 strict concurrency.
//
// The cross-window plumbing has to escape SwiftUI's per-scene
// environment, so a single shared `ComposerEventBus` is constructed
// once on `AppEnvironment.live()` and handed to every scene through
// `\.appEnvironment`. The bus is reference-typed so each scene reads
// the same instance.

import Foundation
import InterlinedDomain

/// One event the composer or the message-detail view emits after a
/// successful write. The Timeline / Detail views translate these into
/// local list mutations.
enum ComposerEvent: Sendable, Equatable {

    /// A brand-new top-level post was created. The Timeline view model
    /// prepends the new message into its rendered list.
    case messageCreated(Message)

    /// A reply was created. The Detail view model for `parentID`
    /// appends the new reply to its `replies` array.
    case replyCreated(parentID: String, reply: Message)

    /// A repost was created. Same Timeline behaviour as a fresh post:
    /// prepend so the user sees it immediately.
    case messageReposted(Message)

    /// An existing message was edited. Any open view rendering the
    /// message swaps it for the updated copy in place.
    case messageUpdated(Message)

    /// A message was deleted. Open views remove the corresponding row.
    case messageDeleted(id: String)
}

/// Shared event bus. Use `events()` to obtain a subscription stream;
/// terminate the stream by cancelling the consuming task.
final class ComposerEventBus: Sendable {

    /// Subscriber registry. Shared with the other three feature buses; see
    /// `EventBusStorage` for why registration is synchronous (GitHub #82).
    private let storage = EventBusStorage<ComposerEvent>()

    init() {}

    /// Returns an `AsyncStream` that yields every event posted after
    /// subscription. The subscriber is registered before this returns, so an
    /// immediately-following `post` is delivered. The stream finishes when the
    /// consuming task is cancelled.
    func events() -> AsyncStream<ComposerEvent> {
        storage.stream()
    }

    /// Publish an event to every active subscriber. Late subscribers do not
    /// receive past events. Delivery is synchronous with the call.
    func post(_ event: ComposerEvent) {
        storage.broadcast(event)
    }

    /// Live subscriber count, for tests that need to assert a subscription
    /// exists rather than wait for one.
    var subscriberCount: Int { storage.subscriberCount }
}
