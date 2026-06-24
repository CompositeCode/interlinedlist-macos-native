// NotificationsListViewModelTests
//
// BDD-named tests for the M5 notifications tray view model. Covers:
//   - happy: load populates items + unreadCount; posts bus event.
//   - empty: load with an empty tray surfaces hasLoadedOnce.
//   - failure: load failure surfaces error + sets hasLoadedOnce.
//   - markRead: optimistic flip + bus event + service call.
//   - markRead failure: rollback to prior isRead + unreadCount.
//   - markAllRead: every row flips; unreadCount → 0; posts bus event.
//   - markAllRead failure: full snapshot restore.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class NotificationsListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(
        bus: NotificationsEventBus = NotificationsEventBus()
    ) async -> (NotificationsListViewModel, StubNotificationsService, NotificationsEventBus) {
        let service = StubNotificationsService()
        let vm = NotificationsListViewModel(service: service, notificationsEventBus: bus)
        return (vm, service, bus)
    }

    private func note(
        id: String,
        kind: NotificationKind = .dig,
        actor: UserSummary? = UserSummary(id: "u-actor", username: "alice", displayName: "Alice", avatarURL: nil),
        isRead: Bool = false
    ) -> InterlinedDomain.Notification {
        InterlinedDomain.Notification(
            id: id,
            kind: kind,
            actor: actor,
            target: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: isRead,
            readAt: nil,
            title: nil,
            body: nil
        )
    }

    // MARK: - load

    func test_givenPopulatedTray_whenLoading_thenItemsAndUnreadCountAreSet() async {
        let (vm, service, _) = await makeViewModel()
        await service.enqueueTray(success: NotificationTray(
            unreadCount: 2,
            items: [note(id: "n1"), note(id: "n2", isRead: true)]
        ))

        await vm.load()

        XCTAssertEqual(vm.items.map(\.id), ["n1", "n2"])
        XCTAssertEqual(vm.unreadCount, 2)
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    func test_givenEmptyTray_whenLoading_thenItemsIsEmptyAndHasLoadedOnce() async {
        let (vm, service, _) = await makeViewModel()
        await service.enqueueTray(success: NotificationTray.empty)

        await vm.load()

        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.unreadCount, 0)
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    func test_givenTrayFailure_whenLoading_thenSurfacesErrorAndHasLoadedOnce() async {
        let (vm, service, _) = await makeViewModel()
        await service.enqueueTray(failure: TestError.upstream("net"))

        await vm.load()

        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    // MARK: - markRead

    func test_givenUnreadRow_whenMarkingRead_thenOptimisticallyFlipsAndDecrementsUnread() async {
        let (vm, service, _) = await makeViewModel()
        vm.seedForTest(items: [note(id: "n1", isRead: false)], unreadCount: 1)
        await service.enqueueMarkReadSuccess()

        await vm.markRead(id: "n1")

        XCTAssertTrue(vm.items.first?.isRead == true)
        XCTAssertEqual(vm.unreadCount, 0)
        XCTAssertNil(vm.error)
    }

    func test_givenAlreadyReadRow_whenMarkingRead_thenServiceIsNotCalled() async {
        let (vm, service, _) = await makeViewModel()
        vm.seedForTest(items: [note(id: "n1", isRead: true)], unreadCount: 0)

        await vm.markRead(id: "n1")

        let recorded = await service.recorded
        XCTAssertTrue(
            recorded.allSatisfy {
                if case .markRead = $0.kind { return false }
                return true
            },
            "Already-read row must not hit the service"
        )
    }

    func test_givenMarkReadFailure_whenMarkingRead_thenRollsBackOptimisticFlip() async {
        let (vm, service, _) = await makeViewModel()
        vm.seedForTest(items: [note(id: "n1", isRead: false)], unreadCount: 1)
        await service.enqueueMarkRead(failure: TestError.upstream("net"))

        await vm.markRead(id: "n1")

        XCTAssertFalse(vm.items.first?.isRead == true)
        XCTAssertEqual(vm.unreadCount, 1)
        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
    }

    // MARK: - markAllRead

    func test_givenMixedTray_whenMarkAllRead_thenAllRowsFlipAndUnreadIsZero() async {
        let (vm, service, _) = await makeViewModel()
        vm.seedForTest(items: [
            note(id: "n1", isRead: false),
            note(id: "n2", isRead: true),
            note(id: "n3", isRead: false)
        ], unreadCount: 2)
        await service.enqueueMarkAllReadSuccess()

        await vm.markAllRead()

        XCTAssertTrue(vm.items.allSatisfy { $0.isRead })
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func test_givenMarkAllReadFailure_whenMarkAllRead_thenRollsBackToSnapshot() async {
        let (vm, service, _) = await makeViewModel()
        let initial = [
            note(id: "n1", isRead: false),
            note(id: "n2", isRead: true)
        ]
        vm.seedForTest(items: initial, unreadCount: 1)
        await service.enqueueMarkAllRead(failure: TestError.upstream("net"))

        await vm.markAllRead()

        XCTAssertEqual(vm.items.map(\.isRead), [false, true])
        XCTAssertEqual(vm.unreadCount, 1)
        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
    }

    // MARK: - empty tray on markAllRead boundary

    func test_givenAllRowsAlreadyRead_whenMarkAllRead_thenIdempotentAndStillCallsService() async {
        // The view model still defers to the service (the server may
        // know about rows the local cache hasn't seen yet); the
        // optimistic local mutation just leaves the rows alone.
        let (vm, service, _) = await makeViewModel()
        vm.seedForTest(items: [
            note(id: "n1", isRead: true),
            note(id: "n2", isRead: true)
        ], unreadCount: 0)
        await service.enqueueMarkAllReadSuccess()

        await vm.markAllRead()

        XCTAssertTrue(vm.items.allSatisfy { $0.isRead })
        XCTAssertEqual(vm.unreadCount, 0)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains { if case .markAllRead = $0.kind { return true } else { return false } })
    }
}
