import XCTest
@testable import InterlinedKit

/// BDD tests for the Direct Messages endpoint group (the-gaps.md G1).
/// Fixtures mirror the shapes captured live 2026-07-31.
final class DirectMessagesEndpointTests: XCTestCase {

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

    /// A DM row exactly as the live API returns it (fractional-second date,
    /// embedded sender/recipient).
    private func dmJSON(id: String) -> String {
        #"""
        {"id":"\#(id)","pairKey":"s:r","senderId":"s","recipientId":"r",
         "body":"hi there","imageUrls":[],
         "createdAt":"2026-07-31T22:20:32.337Z","readAt":null,
         "sender":{"id":"s","username":"messenger","displayName":"Messenger","avatar":"https://cdn/s.png"},
         "recipient":{"id":"r","username":"adron","displayName":"Adron","avatar":"https://cdn/r.png"},
         "preview":"hi there"}
        """#
    }

    // MARK: - Builder shape assertions

    func test_givenDMBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(DirectMessages.folder("sent").path, "/api/dm")
        XCTAssertEqual(DirectMessages.folder("sent").query.first(where: { $0.name == "folder" })?.value, "sent")
        XCTAssertEqual(DirectMessages.send(SendDirectMessageRequest(recipientId: "r", body: "hi")).method, .post)
        XCTAssertEqual(DirectMessages.thread(username: "adron").path, "/api/dm/thread/adron")
        XCTAssertEqual(DirectMessages.threadUpdates(username: "adron").path, "/api/dm/thread/adron/updates")
        XCTAssertEqual(DirectMessages.recipients().path, "/api/dm/recipients")
        XCTAssertEqual(DirectMessages.unreadCount().path, "/api/dm/unread-count")
        XCTAssertEqual(DirectMessages.markRead(id: "m1").path, "/api/dm/m1/read")
        XCTAssertEqual(DirectMessages.trash(id: "m1").path, "/api/dm/m1/trash")
        XCTAssertEqual(DirectMessages.trash(id: "m1").method, .post)
        XCTAssertEqual(DirectMessages.restore(id: "m1").path, "/api/dm/m1/restore")
    }

    // MARK: - Happy path

    func test_givenFolderBody_whenSent_thenDecodesItemsAndCursor() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"items":[\#(dmJSON(id: "m1"))],"nextCursor":"c2"}"#))

        let page = try await client.send(DirectMessages.folder("inbox"))

        XCTAssertEqual(page.items.map(\.id), ["m1"])
        XCTAssertEqual(page.items.first?.sender?.username, "messenger")
        XCTAssertEqual(page.nextCursor, "c2")
    }

    func test_givenCreateBody_whenSendSent_thenDecodesWrappedMessageAndEncodesBody() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"message":\#(dmJSON(id: "m9"))}"#))

        let response = try await client.send(
            DirectMessages.send(SendDirectMessageRequest(recipientId: "r", body: "hi there"))
        )

        XCTAssertEqual(response.message.id, "m9")
        let received = await transport.received
        let body = try XCTUnwrap(received[0].httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["recipientId"] as? String, "r")
        XCTAssertEqual(json?["body"] as? String, "hi there")
    }

    func test_givenThreadBody_whenSent_thenDecodesItemsAndMetadata() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"items":[\#(dmJSON(id: "m1"))],"olderCursor":null,"isMutual":true,"isBlocked":false,
         "otherUser":{"id":"r","username":"adron","displayName":"Adron","avatar":"https://cdn/r.png"}}
        """#))

        let thread = try await client.send(DirectMessages.thread(username: "adron"))

        XCTAssertEqual(thread.items.map(\.id), ["m1"])
        XCTAssertEqual(thread.isMutual, true)
        XCTAssertEqual(thread.otherUser?.username, "adron")
    }

    func test_givenRecipientsBody_whenSent_thenDecodesUsers() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"recipients":[{"id":"r","username":"adron","displayName":"Adron"}]}"#))

        let response = try await client.send(DirectMessages.recipients())

        XCTAssertEqual(response.recipients.map(\.id), ["r"])
    }

    func test_givenUnreadCountBody_whenSent_thenDecodesCount() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"count":3}"#))

        let response = try await client.send(DirectMessages.unreadCount())

        XCTAssertEqual(response.count, 3)
    }

    // MARK: - API failure

    func test_givenForbidden_whenSendSent_thenThrowsForbidden() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"not mutual followers"}"#, status: 403))

        do {
            _ = try await client.send(DirectMessages.send(SendDirectMessageRequest(recipientId: "r", body: "hi")))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "not mutual followers"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenEmptyFolder_whenSent_thenReturnsNoItems() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"items":[],"nextCursor":null}"#))

        let page = try await client.send(DirectMessages.folder("deleted"))

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertNil(page.nextCursor)
    }
}
