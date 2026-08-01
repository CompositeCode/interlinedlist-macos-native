// DirectMessagesUnreadBadgeCoordinatorTests
//
// BDD-named tests for the DM badge coordinator's pure fold logic and for
// the `UnreadBadgeAggregator` that sums the notifications + DM slots
// (the-gaps.md G1). The coordinator's stream plumbing is not exercised
// here (it's the same shape as the notifications coordinator, whose glue
// is already covered); we test the fold and the aggregation math, which
// is where the "don't regress the notifications badge" contract lives.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DirectMessagesUnreadBadgeCoordinatorTests: XCTestCase {

    private func makeCoordinator() -> DirectMessagesUnreadBadgeCoordinator {
        DirectMessagesUnreadBadgeCoordinator(
            bus: DirectMessagesEventBus(),
            reportCount: { _ in }
        )
    }

    // MARK: - fold

    func test_givenUnreadCountChanged_whenFolding_thenReturnsThatCount() async {
        let coordinator = makeCoordinator()

        let count = await coordinator.fold(event: .unreadCountChanged(5))

        XCTAssertEqual(count, 5)
    }

    func test_givenNegativeUnreadCount_whenFolding_thenClampsToZero() async {
        let coordinator = makeCoordinator()

        let count = await coordinator.fold(event: .unreadCountChanged(-3))

        XCTAssertEqual(count, 0)
    }

    func test_givenThreadRead_whenFolding_thenReturnsLastKnownCount() async {
        let coordinator = makeCoordinator()
        _ = await coordinator.fold(event: .unreadCountChanged(4))

        let count = await coordinator.fold(event: .threadRead(username: "ada"))

        XCTAssertEqual(count, 4, "threadRead holds the last-known total until the authoritative count arrives")
    }

    func test_givenMessageSent_whenFolding_thenDoesNotChangeOwnUnread() async {
        let coordinator = makeCoordinator()
        _ = await coordinator.fold(event: .unreadCountChanged(2))

        let count = await coordinator.fold(event: fixtureSentEvent())

        XCTAssertEqual(count, 2, "Sending a message never changes your own unread count")
    }

    // MARK: - Aggregator (non-regression: sum both sources)

    func test_givenBothSources_whenUpdated_thenBadgeShowsSum() async {
        var written: [Int] = []
        let aggregator = UnreadBadgeAggregator(writeBadge: { written.append($0) })

        aggregator.update(source: .notifications, count: 3)
        aggregator.update(source: .directMessages, count: 2)

        XCTAssertEqual(aggregator.total, 5, "The dock badge sums both unread sources")
        XCTAssertEqual(written.last, 5)
    }

    func test_givenDMUpdate_whenNotificationsUnchanged_thenNotificationsContributionSurvives() async {
        var written: [Int] = []
        let aggregator = UnreadBadgeAggregator(writeBadge: { written.append($0) })
        aggregator.update(source: .notifications, count: 7)

        // A DM update must not clobber the notifications contribution.
        aggregator.update(source: .directMessages, count: 1)

        XCTAssertEqual(aggregator.total, 8)
        XCTAssertEqual(written.last, 8, "DMs add to, never replace, the notifications badge")
    }

    func test_givenNegativeSourceCount_whenUpdated_thenClampsToZero() async {
        var written: [Int] = []
        let aggregator = UnreadBadgeAggregator(writeBadge: { written.append($0) })

        aggregator.update(source: .directMessages, count: -4)

        XCTAssertEqual(aggregator.total, 0)
        XCTAssertEqual(written.last, 0)
    }

    // MARK: - Fixture

    private func fixtureSentEvent() -> DirectMessagesEvent {
        let dm = DirectMessage(
            id: "m1", senderId: "user-me", recipientId: "user-ada", body: "hi",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        return .messageSent(recipientUsername: "ada", message: dm)
    }
}
