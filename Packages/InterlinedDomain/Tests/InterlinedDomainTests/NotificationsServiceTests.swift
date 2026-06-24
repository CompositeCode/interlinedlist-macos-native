import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `NotificationsService` (PLAN.md §1 "Notifications",
/// §6 M5, §7 testing). Quartet per public method: happy + invalid + failure
/// + empty/boundary.
final class NotificationsServiceTests: XCTestCase {

    // MARK: - tray

    func test_givenTrayWithUnreadAndItems_whenLoadingTray_thenMapsBothFields() async throws {
        // Given
        let api = StubAPIClient()
        let items = [
            Fixtures.notificationObject(
                id: "n-1",
                type: "dig",
                title: "Ada dug your post",
                metadataJSON: #"{"messageId":"m-1","actorId":"u-1","actorUsername":"ada","actorDisplayName":"Ada Lovelace","actorAvatar":"https://cdn/ada.png"}"#
            ),
            Fixtures.notificationObject(
                id: "n-2",
                type: "reply",
                title: "Hopper replied",
                metadataJSON: #"{"messageId":"m-2","actorId":"u-2"}"#,
                readAt: Fixtures.createdAtISO
            )
        ]
        await api.enqueue(json: Fixtures.notificationTrayEnvelope(unreadCount: 1, items: items))
        let service = NotificationsService(api: api)

        // When
        let tray = try await service.tray()

        // Then — counts and items both mapped.
        XCTAssertEqual(tray.unreadCount, 1)
        XCTAssertEqual(tray.items.map(\.id), ["n-1", "n-2"])
        XCTAssertEqual(tray.items.first?.kind, .dig)
        XCTAssertEqual(tray.items.first?.target, .message(id: "m-1"))
        XCTAssertEqual(tray.items.first?.actor?.id, "u-1")
        XCTAssertFalse(tray.items.first?.isRead ?? true)
        // The second row is marked read (readAt present).
        XCTAssertTrue(tray.items.last?.isRead ?? false)

        // And — the request shape carries `scope=tray`.
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/notifications")
        XCTAssertEqual(recorded.first?.query["scope"], "tray")
    }

    func test_givenMalformedTray_whenLoadingTray_thenThrowsDecoding() async throws {
        // Given — invalid input: missing `items` key.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"unreadCount":3}"#)
        let service = NotificationsService(api: api)

        // When / Then
        do {
            _ = try await service.tray()
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }

    func test_givenTrayEndpointFails_whenLoadingTray_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = NotificationsService(api: api)

        // When / Then
        do {
            _ = try await service.tray()
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenEmptyTray_whenLoadingTray_thenReturnsEmptyValue() async throws {
        // Given — boundary: brand-new account, nothing in the tray.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.notificationTrayEnvelope(unreadCount: 0, items: []))
        let service = NotificationsService(api: api)

        // When
        let tray = try await service.tray()

        // Then
        XCTAssertEqual(tray, .empty)
        XCTAssertEqual(tray.unreadCount, 0)
        XCTAssertTrue(tray.items.isEmpty)
    }

    // MARK: - markRead

    func test_givenSingleNotification_whenMarkingRead_thenSucceeds() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.notificationReadResponse)
        let service = NotificationsService(api: api)

        // When
        try await service.markRead(id: "n-1")

        // Then — request shape is `PATCH /api/notifications/<id>/read`.
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
        XCTAssertEqual(recorded.first?.path, "/api/notifications/n-1/read")
    }

    func test_givenMarkReadFails_whenMarkingRead_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no such notification"))
        let service = NotificationsService(api: api)

        // When / Then
        do {
            try await service.markRead(id: "n-missing")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no such notification"))
        }
    }

    func test_givenEmptyId_whenMarkingRead_thenAPIBadRequestPropagates() async throws {
        // Given — invalid input boundary: empty id. The API responds 400.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "missing id"))
        let service = NotificationsService(api: api)

        // When / Then
        do {
            try await service.markRead(id: "")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "missing id"))
        }
    }

    // MARK: - markAllRead

    func test_givenSeveralUnread_whenMarkingAllRead_thenSucceeds() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.notificationMarkAllReadResponse(updated: 5))
        let service = NotificationsService(api: api)

        // When
        try await service.markAllRead()

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/notifications/mark-all-read")
    }

    func test_givenMarkAllReadFails_whenMarkingAllRead_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = NotificationsService(api: api)

        // When / Then
        do {
            try await service.markAllRead()
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport(message: "offline"))
        }
    }

    func test_givenAlreadyEmpty_whenMarkingAllRead_thenSucceedsWithZeroUpdated() async throws {
        // Given — boundary: nothing unread to update.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.notificationMarkAllReadResponse(updated: 0))
        let service = NotificationsService(api: api)

        // When / Then — no throw.
        try await service.markAllRead()
    }
}
