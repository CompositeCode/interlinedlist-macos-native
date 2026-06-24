import XCTest
import InterlinedDomain
@testable import InterlinedPersistence

/// BDD-named coverage for `SwiftDataNotificationStore` (PLAN.md §1
/// "Notifications", §5 stale-while-revalidate, §6 M5, §7 testing).
final class SwiftDataNotificationStoreTests: XCTestCase {

    // MARK: - Tray round-trip

    func test_givenReplacedTray_whenReadingTray_thenReturnsItemsInOrder() async throws {
        // Given
        let store = try SwiftDataNotificationStore.inMemory()
        let tray = NotificationTray(
            unreadCount: 2,
            items: [
                sampleNotification(id: "a", title: "first"),
                sampleNotification(id: "b", title: "second"),
                sampleNotification(id: "c", title: "third")
            ]
        )

        // When
        await store.replaceTray(tray)

        // Then
        let cached = await store.cachedTray()
        XCTAssertEqual(cached.unreadCount, 2)
        XCTAssertEqual(cached.items.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(cached.items.map(\.title), ["first", "second", "third"])
    }

    func test_givenEmptyStore_whenReadingTray_thenReturnsEmptyValue() async throws {
        // Given
        let store = try SwiftDataNotificationStore.inMemory()

        // When
        let tray = await store.cachedTray()

        // Then
        XCTAssertEqual(tray, .empty)
    }

    func test_givenReplacedTrayTwice_whenReading_thenLatestWins() async throws {
        // Given
        let store = try SwiftDataNotificationStore.inMemory()
        await store.replaceTray(NotificationTray(
            unreadCount: 5,
            items: [
                sampleNotification(id: "old-1"),
                sampleNotification(id: "old-2")
            ]
        ))

        // When
        await store.replaceTray(NotificationTray(
            unreadCount: 1,
            items: [sampleNotification(id: "new-1")]
        ))

        // Then — the second replace fully supersedes the first metadata row.
        let tray = await store.cachedTray()
        XCTAssertEqual(tray.unreadCount, 1)
        XCTAssertEqual(tray.items.map(\.id), ["new-1"])
    }

    // MARK: - by-id reads

    func test_givenReplacedTray_whenReadingByID_thenAlsoIndexed() async throws {
        // Given — replaceTray must populate the by-id store too.
        let store = try SwiftDataNotificationStore.inMemory()
        await store.replaceTray(NotificationTray(
            unreadCount: 1,
            items: [sampleNotification(id: "a")]
        ))

        // When
        let byID = await store.cachedNotification(id: "a")

        // Then
        XCTAssertEqual(byID?.id, "a")
    }

    func test_givenMissingID_whenReadingByID_thenReturnsNil() async throws {
        // Given — empty store.
        let store = try SwiftDataNotificationStore.inMemory()

        // When
        let result = await store.cachedNotification(id: "ghost")

        // Then
        XCTAssertNil(result)
    }

    // MARK: - markRead

    func test_givenUnreadNotification_whenMarkingRead_thenFlagFlipsAndUnreadDecrements() async throws {
        // Given — cache with one unread row and `unreadCount: 1`.
        let store = try SwiftDataNotificationStore.inMemory()
        await store.replaceTray(NotificationTray(
            unreadCount: 1,
            items: [sampleNotification(id: "a", isRead: false)]
        ))

        // When
        await store.markRead(id: "a")

        // Then — row flagged read, `readAt` set, badge decrements.
        let row = await store.cachedNotification(id: "a")
        XCTAssertTrue(row?.isRead ?? false)
        XCTAssertNotNil(row?.readAt)
        let tray = await store.cachedTray()
        XCTAssertEqual(tray.unreadCount, 0)
    }

    func test_givenAlreadyReadNotification_whenMarkingRead_thenUnreadCountUnchanged() async throws {
        // Given — boundary: the row is already read; badge must not go below zero.
        let store = try SwiftDataNotificationStore.inMemory()
        await store.replaceTray(NotificationTray(
            unreadCount: 0,
            items: [sampleNotification(id: "a", isRead: true)]
        ))

        // When
        await store.markRead(id: "a")

        // Then
        let tray = await store.cachedTray()
        XCTAssertEqual(tray.unreadCount, 0)
    }

    func test_givenMissingID_whenMarkingRead_thenNoOp() async throws {
        // Given — boundary: nothing in cache.
        let store = try SwiftDataNotificationStore.inMemory()
        await store.replaceTray(NotificationTray(
            unreadCount: 3,
            items: []
        ))

        // When
        await store.markRead(id: "ghost")

        // Then — unchanged.
        let tray = await store.cachedTray()
        XCTAssertEqual(tray.unreadCount, 3)
    }

    // MARK: - markAllRead

    func test_givenSeveralUnread_whenMarkingAllRead_thenAllFlippedAndBadgeZeroed() async throws {
        // Given
        let store = try SwiftDataNotificationStore.inMemory()
        await store.replaceTray(NotificationTray(
            unreadCount: 3,
            items: [
                sampleNotification(id: "a", isRead: false),
                sampleNotification(id: "b", isRead: false),
                sampleNotification(id: "c", isRead: true)
            ]
        ))

        // When
        await store.markAllRead()

        // Then
        let tray = await store.cachedTray()
        XCTAssertEqual(tray.unreadCount, 0)
        XCTAssertTrue(tray.items.allSatisfy { $0.isRead })
    }

    // MARK: - clear

    func test_givenPopulatedStore_whenCleared_thenTrayAndByIDCachesBothEmpty() async throws {
        // Given
        let store = try SwiftDataNotificationStore.inMemory()
        await store.replaceTray(NotificationTray(
            unreadCount: 2,
            items: [
                sampleNotification(id: "a"),
                sampleNotification(id: "b")
            ]
        ))
        await store.upsert([sampleNotification(id: "c")])

        // When
        await store.clear()

        // Then
        let tray = await store.cachedTray()
        let a = await store.cachedNotification(id: "a")
        let c = await store.cachedNotification(id: "c")
        XCTAssertEqual(tray, .empty)
        XCTAssertNil(a)
        XCTAssertNil(c)
    }

    // MARK: - Target round-trip per kind

    func test_givenEveryTargetCase_whenRoundTripping_thenPreserved() async throws {
        // Given — one row per `NotificationTarget` case so the
        // flat-fields encoding/decoding holds for every shape.
        let store = try SwiftDataNotificationStore.inMemory()
        let rows: [InterlinedDomain.Notification] = [
            sampleNotification(id: "m", kind: .dig, target: .message(id: "msg-1")),
            sampleNotification(id: "l", kind: .listShared, target: .list(id: "list-1")),
            sampleNotification(id: "u", kind: .followAccepted, target: .user(id: "user-1")),
            sampleNotification(id: "o", kind: .orgInvite, target: .organization(id: "org-1")),
            sampleNotification(
                id: "x",
                kind: .other("future_kind"),
                target: .unknown(actionURL: URL(string: "https://interlinedlist.com/x"))
            )
        ]
        await store.replaceTray(NotificationTray(unreadCount: 5, items: rows))

        // When
        let cached = await store.cachedTray()

        // Then — every row round-trips identically (id-keyed comparison).
        for row in rows {
            let matched = cached.items.first(where: { $0.id == row.id })
            XCTAssertEqual(matched?.target, row.target, "round-trip broke for \(row.id)")
            XCTAssertEqual(matched?.kind, row.kind, "kind broke for \(row.id)")
        }
    }

    // MARK: - Helpers

    private func sampleNotification(
        id: String,
        kind: NotificationKind = .dig,
        target: NotificationTarget? = .message(id: "msg-1"),
        title: String = "Sample",
        isRead: Bool = false
    ) -> InterlinedDomain.Notification {
        InterlinedDomain.Notification(
            id: id,
            kind: kind,
            actor: UserSummary(
                id: "user-x",
                username: "ada",
                displayName: "Ada Lovelace",
                avatarURL: URL(string: "https://cdn/ada.png")
            ),
            target: target,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            isRead: isRead,
            readAt: isRead ? Date(timeIntervalSince1970: 1_500_000) : nil,
            title: title,
            body: nil
        )
    }
}
