import XCTest
@testable import InterlinedKit

/// BDD tests for the Direct Messages endpoint group (work-consolidation.md G1).
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

    // MARK: - G22: conversations, single message, image upload
    //
    // Routes probed live 2026-09-09, read-only. The *populated* conversations
    // shape could not be captured (empty inbox on a shared test account,
    // writes not permitted), which is exactly why the decoder is permissive —
    // these cases pin that tolerance so a shape change degrades a field
    // instead of failing the page.

    // MARK: Builder shapes

    func test_givenG22Builders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(DirectMessages.conversations().path, "/api/dm/conversations")
        XCTAssertEqual(DirectMessages.conversations().method, .get)
        XCTAssertEqual(DirectMessages.conversations().auth, .bearer)
        XCTAssertEqual(
            DirectMessages.conversations(cursor: "c9").query.first(where: { $0.name == "cursor" })?.value,
            "c9"
        )
        XCTAssertNil(
            DirectMessages.conversations().query.first(where: { $0.name == "cursor" })?.value,
            "A nil cursor carries no value, so the URL builder drops it"
        )
        XCTAssertEqual(DirectMessages.message(id: "m1").path, "/api/dm/m1")
        XCTAssertEqual(DirectMessages.message(id: "m1").method, .get)
        XCTAssertEqual(DirectMessages.uploadImage(Data([0x1]), contentType: "image/png").path,
                       "/api/dm/images/upload")
        XCTAssertEqual(DirectMessages.uploadImage(Data([0x1]), contentType: "image/png").method, .post)
    }

    // MARK: Happy path

    func test_givenNestedConversationRow_whenSent_thenDecodesParticipantUnreadAndMessage() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"items":[{"pairKey":"s:r","unreadCount":3,
                   "otherUser":{"id":"s","username":"messenger","displayName":"Messenger","avatar":null},
                   "lastMessage":\#(dmJSON(id: "m1"))}],
         "nextCursor":"c2"}
        """#))

        let page = try await client.send(DirectMessages.conversations())

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.pairKey, "s:r")
        XCTAssertEqual(page.items.first?.unreadCount, 3)
        XCTAssertEqual(page.items.first?.otherUser?.username, "messenger")
        XCTAssertEqual(page.items.first?.lastMessage?.id, "m1")
        XCTAssertEqual(page.nextCursor, "c2")
    }

    func test_givenFlattenedConversationRow_whenSent_thenDecodesTheRowAsItsOwnMessage() async throws {
        // The natural output of a `GROUP BY pairKey`: the row *is* the newest
        // message. Both shapes must survive because we could not verify which
        // one the server actually sends.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"items":[\#(dmJSON(id: "m7"))],"nextCursor":null}"#))

        let page = try await client.send(DirectMessages.conversations())

        XCTAssertEqual(page.items.first?.lastMessage?.id, "m7")
        XCTAssertEqual(page.items.first?.pairKey, "s:r", "Read off the message itself")
        XCTAssertEqual(page.items.first?.lastMessage?.sender?.username, "messenger")
    }

    func test_givenAlternateKeySpellings_whenSent_thenStillDecodes() async throws {
        // `latestMessage` / `user` / `unread` instead of the primary spellings.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"items":[{"conversationKey":"a:b","unread":1,
                   "user":{"id":"s","username":"alt","displayName":"Alt","avatar":null},
                   "latestMessage":\#(dmJSON(id: "m3"))}],
         "nextCursor":null}
        """#))

        let page = try await client.send(DirectMessages.conversations())

        XCTAssertEqual(page.items.first?.pairKey, "a:b")
        XCTAssertEqual(page.items.first?.unreadCount, 1)
        XCTAssertEqual(page.items.first?.otherUser?.username, "alt")
        XCTAssertEqual(page.items.first?.lastMessage?.id, "m3")
    }

    func test_givenWrappedSingleMessage_whenFetchingById_thenDecodesUnderMessageKey() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"message":\#(dmJSON(id: "m5"))}"#))

        let response = try await client.send(DirectMessages.message(id: "m5"))

        XCTAssertEqual(response.message.id, "m5")
    }

    func test_givenBareSingleMessage_whenFetchingById_thenDecodesTheObjectItself() async throws {
        // Documented envelope drift on this API (`POST /api/messages` wraps
        // under `data`), and the 200 body could not be captured — so bare,
        // `data`-wrapped, and `message`-wrapped all decode.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(dmJSON(id: "m6")))

        let response = try await client.send(DirectMessages.message(id: "m6"))

        XCTAssertEqual(response.message.id, "m6")
    }

    func test_givenDataWrappedSingleMessage_whenFetchingById_thenDecodesUnderDataKey() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"data":\#(dmJSON(id: "m8"))}"#))

        let response = try await client.send(DirectMessages.message(id: "m8"))

        XCTAssertEqual(response.message.id, "m8")
    }

    func test_givenImageBytes_whenUploading_thenPostsRawBodyWithItsContentType() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"url":"https://cdn.interlinedlist.com/dm/1.jpg"}"#))
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])

        let response = try await client.send(DirectMessages.uploadImage(bytes, contentType: "image/jpeg"))

        XCTAssertEqual(response.url, "https://cdn.interlinedlist.com/dm/1.jpg")
        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/dm/images/upload")
        XCTAssertEqual(received[0].httpMethod, "POST")
        XCTAssertEqual(received[0].httpBody, bytes, "Raw bytes, not re-encoded")
        XCTAssertEqual(received[0].value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
    }

    // MARK: Invalid / unexpected shape

    func test_givenUnrecognisedConversationKeys_whenSent_thenRowDecodesWithNilFieldsNotAnError() async throws {
        // The G21 link-metadata defect was a decoder that silently produced
        // all-nil. Here nil is the *designed* outcome for an unknown spelling —
        // what must not happen is the whole page failing to decode.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"items":[{"totallyUnknown":"x"}],"nextCursor":null}"#))

        let page = try await client.send(DirectMessages.conversations())

        XCTAssertEqual(page.items.count, 1, "The row survives")
        XCTAssertNil(page.items.first?.pairKey)
        XCTAssertNil(page.items.first?.lastMessage)
        XCTAssertNil(page.items.first?.unreadCount)
    }

    func test_givenWrongTypedUnreadCount_whenSent_thenSkipsItRatherThanFailingThePage() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"items":[{"pairKey":"s:r","unreadCount":"three","lastMessage":\#(dmJSON(id: "m1"))}],
         "nextCursor":null}
        """#))

        let page = try await client.send(DirectMessages.conversations())

        XCTAssertNil(page.items.first?.unreadCount, "A mistyped field degrades to nil")
        XCTAssertEqual(page.items.first?.lastMessage?.id, "m1", "Its siblings still decode")
    }

    func test_givenUnreadableSingleMessageBody_whenFetchingById_thenThrowsDecodingNotSilentNil() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"nothing":"useful"}"#))

        do {
            _ = try await client.send(DirectMessages.message(id: "m1"))
            XCTFail("Expected a decoding failure")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }

    // MARK: Upstream API failure

    func test_givenNotFound_whenFetchingMessageById_thenThrowsNotFoundWithServerMessage() async throws {
        // Exactly what the live route answered for an unknown id on 2026-09-09.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Message not found.","code":"not_found"}"#, status: 404))

        do {
            _ = try await client.send(DirectMessages.message(id: "nope"))
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Message not found."))
        }
    }

    func test_givenForbidden_whenUploadingImage_thenThrowsForbiddenPreservingTheServerWording() async throws {
        // The documented "verified email required" refusal. The wording must
        // survive to the UI — the client does not paraphrase it.
        let (client, transport) = makeClient()
        await transport.enqueue(
            .json(#"{"error":"Please verify your email address to send images."}"#, status: 403)
        )

        do {
            _ = try await client.send(DirectMessages.uploadImage(Data([0x1]), contentType: "image/png"))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(
                error,
                .forbidden(serverMessage: "Please verify your email address to send images.")
            )
            XCTAssertEqual(error.userFacingMessage, "Please verify your email address to send images.")
        }
    }

    // MARK: Empty / boundary

    func test_givenEmptyConversationsPage_whenSent_thenReturnsNoItems() async throws {
        // The exact body the live route returned on 2026-09-09.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"items":[],"nextCursor":null}"#))

        let page = try await client.send(DirectMessages.conversations())

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertNil(page.nextCursor)
    }
}
