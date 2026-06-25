// LiveEntitlementsTests
//
// BDD-named tests for the App-layer half of Deliverable B (PLAN.md §8 —
// live entitlement gating). `LiveEntitlements` is the `Sendable` box the
// domain `MessagesService` gate reads at call time; `CurrentUserStore`
// publishes the live `customerStatus` into it on every resolved session
// state. These prove the backstop honors a subscriber vs a free user and
// re-gates when the session changes.
//
// The domain-layer proof that the gate is evaluated *at call time* against
// the provider lives in `MessagesServiceM6Tests`; this is the App-wiring
// proof that the box reflects the live user.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class LiveEntitlementsTests: XCTestCase {

    private func currentUser(status: CustomerStatus) -> CurrentUser {
        CurrentUser(
            summary: MessageFixtures.author(),
            email: "ada@example.com",
            customerStatus: status,
            isEmailVerified: true,
            isPrivateAccount: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Box defaults + updates

    func test_givenNoUser_whenReadingBox_thenDefaultsToFreeNonSubscriber() {
        // Given — a fresh box (signed-out / unresolved).
        let box = LiveEntitlements()

        // Then — free: no subscriber features.
        XCTAssertFalse(box.current().isSubscriber)
        XCTAssertFalse(box.current().isEnabled(.mediaAttachments))
    }

    func test_givenSubscriberUser_whenBoxUpdated_thenGrantsSubscriberFeatures() {
        // Given
        let box = LiveEntitlements()

        // When
        box.update(user: currentUser(status: .subscriber))

        // Then
        XCTAssertTrue(box.current().isSubscriber)
        XCTAssertTrue(box.current().isEnabled(.crossPosting))
    }

    func test_givenFreeUser_whenBoxUpdated_thenBlocksSubscriberFeatures() {
        // Given
        let box = LiveEntitlements()

        // When
        box.update(user: currentUser(status: .free))

        // Then
        XCTAssertFalse(box.current().isEnabled(.scheduledPosts))
    }

    func test_givenNilUser_whenBoxUpdated_thenResetsToFree() {
        // Given — a box that was a subscriber.
        let box = LiveEntitlements()
        box.update(user: currentUser(status: .subscriber))
        XCTAssertTrue(box.current().isSubscriber)

        // When — session signs out.
        box.update(user: nil)

        // Then
        XCTAssertFalse(box.current().isSubscriber)
    }

    // MARK: - CurrentUserStore publishes into the box

    func test_givenSubscriberSession_whenRestored_thenStorePublishesSubscriberIntoBox() async throws {
        // Given — a session that restores to a subscriber.
        let session = StubSessionManaging()
        let box = LiveEntitlements()
        let store = CurrentUserStore(session: session, liveEntitlements: box)
        await session.enqueueRestore(success: .signedIn(currentUser(status: .subscriber)))

        // When
        _ = try await store.restore()

        // Then — both the UI gate source and the domain backstop reflect it.
        XCTAssertEqual(store.currentUserID, "user-ada")
        XCTAssertTrue(box.current().isSubscriber)
    }

    func test_givenFreeSession_whenRestored_thenStorePublishesFreeIntoBox() async throws {
        // Given — a session that restores to a free account.
        let session = StubSessionManaging()
        let box = LiveEntitlements()
        let store = CurrentUserStore(session: session, liveEntitlements: box)
        await session.enqueueRestore(success: .signedIn(currentUser(status: .free)))

        // When
        _ = try await store.restore()

        // Then
        XCTAssertFalse(box.current().isSubscriber)
    }
}
