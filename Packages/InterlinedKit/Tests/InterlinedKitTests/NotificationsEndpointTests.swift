import XCTest
@testable import InterlinedKit

/// BDD tests for the Notifications endpoint group.
final class NotificationsEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_abc")
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    // MARK: - Builder shape assertions

    func test_givenNotificationBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Notifications.tray().path, "/api/notifications")
        XCTAssertEqual(Notifications.tray().method, .get)
        XCTAssertEqual(Notifications.tray().auth, .bearer)
        XCTAssertEqual(Notifications.tray().query.first(where: { $0.name == "scope" })?.value, "tray")

        XCTAssertEqual(Notifications.markRead(id: "n1").method, .patch)
        XCTAssertEqual(Notifications.markRead(id: "n1").path, "/api/notifications/n1/read")

        XCTAssertEqual(Notifications.markAllRead().method, .post)
        XCTAssertEqual(Notifications.markAllRead().path, "/api/notifications/mark-all-read")
    }

    // MARK: - Happy path

    func test_givenTrayBody_whenTraySent_thenDecodesUnreadCountAndItems() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"unreadCount":2,
         "items":[
           {"id":"n1","title":"New dig","body":"x dug your post","type":"dig","metadata":{"messageId":"m1"},"createdAt":"2026-06-16T00:00:00Z"},
           {"id":"n2","title":"Reply","type":"reply","metadata":{},"readAt":"2026-06-16T01:00:00Z"}
         ]}
        """#))

        let tray = try await client.send(Notifications.tray())

        XCTAssertEqual(tray.unreadCount, 2)
        XCTAssertEqual(tray.items.map(\.id), ["n1", "n2"])
        XCTAssertEqual(tray.items.first?.metadata?["messageId"], .string("m1"))
        XCTAssertNotNil(tray.items.last?.readAt)

        let received = await transport.received
        let comps = URLComponents(url: try XCTUnwrap(received[0].url), resolvingAgainstBaseURL: false)
        XCTAssertTrue(comps?.queryItems?.contains(URLQueryItem(name: "scope", value: "tray")) ?? false)
    }

    func test_givenOkBody_whenMarkReadSent_thenDecodesOk() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"ok":true}"#))

        let result = try await client.send(Notifications.markRead(id: "n1"))

        XCTAssertTrue(result.ok)
        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "PATCH")
    }

    func test_givenUpdatedCount_whenMarkAllReadSent_thenDecodesUpdated() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"ok":true,"updated":5}"#))

        let result = try await client.send(Notifications.markAllRead())

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.updated, 5)
    }

    // MARK: - API failure

    func test_givenServerError_whenTraySent_thenThrowsHttpStatus() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"boom"}"#, status: 500))

        do {
            _ = try await client.send(Notifications.tray())
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenEmptyTray_whenTraySent_thenReturnsZeroUnreadAndNoItems() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"unreadCount":0,"items":[]}"#))

        let tray = try await client.send(Notifications.tray())

        XCTAssertEqual(tray.unreadCount, 0)
        XCTAssertTrue(tray.items.isEmpty)
    }

    func test_givenMalformedTray_whenTraySent_thenThrowsDecodingError() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"unreadCount":"not-a-number","items":[]}"#))

        do {
            _ = try await client.send(Notifications.tray())
            XCTFail("Expected decoding error")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }
}
