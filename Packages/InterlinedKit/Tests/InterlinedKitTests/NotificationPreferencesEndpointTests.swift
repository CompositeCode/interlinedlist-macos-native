import XCTest
@testable import InterlinedKit

/// BDD tests for the notification-preferences endpoint (work-consolidation.md G18).
final class NotificationPreferencesEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient() -> (APIClient, StubHTTPDataTransport) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_abc"),
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        return (APIClient(baseURL: baseURL, transport: transport, authTransport: auth), transport)
    }

    // MARK: - Builder shape

    func test_givenBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        let get = NotificationPreferences.get()
        XCTAssertEqual(get.method, .get)
        XCTAssertEqual(get.path, "/api/user/notification-preferences")
        XCTAssertEqual(get.auth, .bearer)

        let patch = NotificationPreferences.update(
            UpdateNotificationPreferencesRequest(events: [
                .init(key: "dig", channels: NotificationChannelsDTO(push: false, inApp: true))
            ])
        )
        XCTAssertEqual(patch.method, .patch)
        XCTAssertEqual(patch.path, "/api/user/notification-preferences")
        XCTAssertEqual(patch.auth, .bearer)
    }

    // MARK: - Happy path

    func test_givenCatalogueBody_whenSent_thenDecodesLabelsAndChannels() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "events": [
            { "key": "dig", "label": "Digs on your messages",
              "description": "When someone digs a message you wrote.",
              "channels": { "push": true, "inApp": true } },
            { "key": "follow", "label": "New followers",
              "channels": { "push": false, "inApp": true, "email": true } }
        ] }
        """#))

        let response = try await client.send(NotificationPreferences.get())

        XCTAssertEqual(response.events.count, 2)
        XCTAssertEqual(response.events[0].key, "dig")
        XCTAssertEqual(response.events[0].label, "Digs on your messages")
        XCTAssertEqual(response.events[0].channels?.push, true)
        XCTAssertNil(response.events[1].description)
        XCTAssertEqual(response.events[1].channels?.email, true)
    }

    // MARK: - Invalid / tolerant input

    func test_givenEventMissingLabelAndChannels_whenSent_thenStillDecodes() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "events": [ { "key": "mention" } ] }"#))

        let response = try await client.send(NotificationPreferences.get())

        XCTAssertEqual(response.events.map(\.key), ["mention"])
        XCTAssertNil(response.events[0].label)
        XCTAssertNil(response.events[0].channels)
    }

    func test_givenUpdateBody_whenEncoded_thenCarriesOnlyKeyAndChannels() throws {
        let body = UpdateNotificationPreferencesRequest(events: [
            .init(key: "dig", channels: NotificationChannelsDTO(push: false, inApp: true))
        ])

        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(body)
        ) as? [String: Any]
        let events = json?["events"] as? [[String: Any]]

        XCTAssertEqual(events?.count, 1)
        XCTAssertEqual(events?[0]["key"] as? String, "dig")
        XCTAssertNotNil(events?[0]["channels"])
        // Server-owned display fields must never be echoed back.
        XCTAssertNil(events?[0]["label"])
        XCTAssertNil(events?[0]["description"])
    }

    // MARK: - API failure

    func test_givenServerError_whenSent_thenThrowsHttpStatus() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"nope"}"#, status: 500))

        do {
            _ = try await client.send(NotificationPreferences.get())
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            guard case .httpStatus(let code, _) = error else {
                return XCTFail("Expected .httpStatus, got \(error)")
            }
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoEvents_whenSent_thenReturnsEmptyCatalogue() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "events": [] }"#))

        let response = try await client.send(NotificationPreferences.get())

        XCTAssertTrue(response.events.isEmpty)
    }
}
