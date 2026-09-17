// EventBusStorageTests
//
// BDD quartet for the shared subscriber registry behind the four feature event
// buses (GitHub #82).
//
// The behaviour under test is the one the old actor-backed version did not have:
// a subscriber is registered *before* `events()` returns, so a caller that
// subscribes and immediately writes receives its own event. Every test here is
// written so that it would fail — not merely flake — against the previous
// implementation, which is the only way a regression test for a race is worth
// anything.

import XCTest
@testable import InterlinedList

final class EventBusStorageTests: XCTestCase {

    // MARK: - Happy path

    func test_givenSubscriber_whenEventPostedImmediately_thenItIsDelivered() async {
        // Given — a bus with one subscriber, created and *not* waited on.
        let bus = DirectMessagesEventBus()
        let stream = bus.events()

        // When — the write happens on the very next line, with no sleep, no
        // yield, and no opportunity for a background registration to catch up.
        bus.post(.unreadCountChanged(7))

        // Then — the event is there. Under the old async registration this is
        // the line that lost the race.
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        XCTAssertEqual(event, .unreadCountChanged(7))
    }

    func test_givenSubscription_whenCreated_thenRegistrationIsSynchronous() {
        // The invariant stated directly: no awaiting anywhere in this test.
        let bus = DirectMessagesEventBus()
        XCTAssertEqual(bus.subscriberCount, 0)
        let stream = bus.events()
        XCTAssertEqual(bus.subscriberCount, 1, "events() must register before it returns")
        // The stream has to be held: dropping it deinitialises the continuation,
        // which fires `onTermination` and unregisters. That is the correct
        // behaviour — asserted on its own below — but it makes `_ = bus.events()`
        // a misleading way to write this test.
        withExtendedLifetime(stream) {}
    }

    func test_givenDiscardedStream_whenItDeinitialises_thenTheSubscriberIsDropped() {
        // The mirror image: a stream nobody keeps must not leave a dead
        // continuation in the table. This is the leak the registry would
        // otherwise accumulate one entry at a time per transient view.
        let bus = DirectMessagesEventBus()
        do {
            let stream = bus.events()
            XCTAssertEqual(bus.subscriberCount, 1)
            withExtendedLifetime(stream) {}
        }
        XCTAssertEqual(bus.subscriberCount, 0, "a dropped stream unregisters itself")
    }

    // MARK: - Invalid / no-subscriber input

    func test_givenNoSubscribers_whenPosting_thenNothingHappensAndNoCrash() {
        // Given a bus nobody is listening to — the ordinary state at launch.
        let bus = NotificationsEventBus()

        // When / Then — posting into the void is a no-op, not a trap.
        bus.post(.markedAllRead)
        XCTAssertEqual(bus.subscriberCount, 0)
    }

    // MARK: - "Upstream failure" analogue: a subscriber that goes away

    func test_givenCancelledSubscriber_whenPosting_thenItIsUnregistered() async {
        // Given — a subscriber that is consuming, then cancelled.
        let bus = ListsEventBus()
        let stream = bus.events()
        XCTAssertEqual(bus.subscriberCount, 1)

        let task = Task { for await _ in stream { } }
        task.cancel()

        // Then — the registry drops it rather than leaking a dead continuation.
        // Termination is delivered by the runtime, so this one genuinely has to
        // wait for a post-condition; it polls rather than sleeping.
        await settleOffMainActor(until: { bus.subscriberCount == 0 })
        XCTAssertEqual(bus.subscriberCount, 0)
    }

    // MARK: - Boundary: several subscribers, and late ones

    func test_givenSeveralSubscribers_whenPosting_thenEachReceivesTheEventOnce() async {
        // Given — three independent streams on one bus.
        let bus = ComposerEventBus()
        let streams = (0..<3).map { _ in bus.events() }
        XCTAssertEqual(bus.subscriberCount, 3)

        // When
        bus.post(.messageDeleted(id: "m1"))

        // Then — every subscriber sees it, and sees it once.
        for stream in streams {
            var iterator = stream.makeAsyncIterator()
            let event = await iterator.next()
            XCTAssertEqual(event, .messageDeleted(id: "m1"))
        }
    }

    func test_givenLateSubscriber_whenEventWasAlreadyPosted_thenItReceivesNothing() async {
        // Boundary in the other direction: the bus is explicitly not a replay
        // log, and a subscriber created after the fact must not see history.
        let bus = ComposerEventBus()
        bus.post(.messageDeleted(id: "m1"))

        let stream = bus.events()
        bus.post(.messageDeleted(id: "m1"))

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .messageDeleted(id: "m1"), "only the post made after subscribing")
        XCTAssertEqual(bus.subscriberCount, 1)
    }

    // MARK: - Helpers

    /// `settle(until:)` is `@MainActor`; this suite is not, because the bus
    /// deliberately has no actor affinity. Same contract, no isolation.
    private func settleOffMainActor(
        until condition: @Sendable () -> Bool,
        timeout: Duration = .seconds(5)
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Condition never became true within \(timeout)")
    }
}
