// NotificationsUnreadBadgeCoordinatorTests
//
// BDD-named tests for the dock-badge folding logic. Asserts:
//   - trayRefreshed snapshots the count.
//   - markedRead decrements from the last known count.
//   - markedAllRead zeroes the count.
//   - request approve / reject are no-ops on the count itself.
//   - decrement is clamped at zero.

import XCTest
@testable import InterlinedList

@MainActor
final class NotificationsUnreadBadgeCoordinatorTests: XCTestCase {

    private func makeCoordinator() -> (NotificationsUnreadBadgeCoordinator, NotificationsEventBus) {
        let bus = NotificationsEventBus()
        let coordinator = NotificationsUnreadBadgeCoordinator(
            bus: bus,
            writeBadge: { _ in }
        )
        return (coordinator, bus)
    }

    func test_givenFreshCoordinator_whenTrayRefreshed_thenLastKnownCountUpdates() async {
        let (coord, _) = makeCoordinator()
        let value = await coord.fold(event: .trayRefreshed(unreadCount: 4))
        XCTAssertEqual(value, 4)
    }

    func test_givenKnownCount_whenMarkedRead_thenDecrementsByOne() async {
        let (coord, _) = makeCoordinator()
        _ = await coord.fold(event: .trayRefreshed(unreadCount: 3))
        let value = await coord.fold(event: .markedRead(id: "n1"))
        XCTAssertEqual(value, 2)
    }

    func test_givenZeroCount_whenMarkedRead_thenClampsAtZero() async {
        let (coord, _) = makeCoordinator()
        _ = await coord.fold(event: .trayRefreshed(unreadCount: 0))
        let value = await coord.fold(event: .markedRead(id: "n1"))
        XCTAssertEqual(value, 0)
    }

    func test_givenKnownCount_whenMarkedAllRead_thenCountBecomesZero() async {
        let (coord, _) = makeCoordinator()
        _ = await coord.fold(event: .trayRefreshed(unreadCount: 7))
        let value = await coord.fold(event: .markedAllRead)
        XCTAssertEqual(value, 0)
    }

    func test_givenRequestApproved_whenFolding_thenCountIsUnchanged() async {
        let (coord, _) = makeCoordinator()
        _ = await coord.fold(event: .trayRefreshed(unreadCount: 5))
        let value = await coord.fold(event: .requestApproved(requestUserID: "u1"))
        XCTAssertEqual(value, 5)
    }

    func test_givenRequestRejected_whenFolding_thenCountIsUnchanged() async {
        let (coord, _) = makeCoordinator()
        _ = await coord.fold(event: .trayRefreshed(unreadCount: 5))
        let value = await coord.fold(event: .requestRejected(requestUserID: "u1"))
        XCTAssertEqual(value, 5)
    }

    func test_givenNoKnownCount_whenMarkedAllReadFirst_thenCountIsZero() async {
        // Boundary: a mark-all-read posted before any tray refresh
        // still resolves to zero (the user implicitly knows they
        // read everything).
        let (coord, _) = makeCoordinator()
        let value = await coord.fold(event: .markedAllRead)
        XCTAssertEqual(value, 0)
    }
}
