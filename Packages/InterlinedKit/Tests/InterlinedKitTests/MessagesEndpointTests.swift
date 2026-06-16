import XCTest
@testable import InterlinedKit

/// BDD tests for the `Messages` endpoint builders and their DTOs.
///
/// Two complementary layers are exercised:
/// 1. **Builder shape** — pure assertions on the `Request` value (method, path,
///    query nil-skipping, auth, body encoding, `paginationKey`). No network.
/// 2. **End-to-end decode** — the builder's request is sent through `APIClient`
///    against `StubHTTPDataTransport`, proving the live response shape decodes
///    into the DTOs (happy path, API failure, empty/boundary).
///
/// Paginated endpoints (`Paginated<T>`) are not `Decodable` and so are not sent
/// through `send(_:)`; instead the builder's `paginationKey` is fed to
/// `PaginatedDecoder` exactly as the domain layer / `PageIterator` will, which
/// is the realistic consumption path.
final class MessagesEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_test")
    ) -> (APIClient, StubHTTPDataTransport) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    private func encodedBody(_ request: Request<some Any>) throws -> [String: Any] {
        guard case .json(let value) = request.body else {
            XCTFail("Expected a JSON body"); return [:]
        }
        let data = try JSONCoders.makeEncoder().encode(AnyEncodableProbe(value))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object ?? [:]
    }

    // A real message JSON fixture matching the live API shape.
    private let messageJSON = #"""
    {
      "id": "m1",
      "content": "Hello **world**",
      "publiclyVisible": true,
      "userId": "u1",
      "parentId": null,
      "linkMetadata": null,
      "imageUrls": null,
      "videoUrls": null,
      "crossPostUrls": null,
      "scheduledAt": null,
      "tags": ["swift", "macos"],
      "createdAt": "2026-06-16T12:00:00.000Z",
      "updatedAt": "2026-06-16T12:00:00.000Z",
      "digCount": 3,
      "pushCount": 1,
      "pushedMessageId": null,
      "user": { "id": "u1", "username": "ada", "displayName": "Ada", "avatar": null },
      "pushedMessage": null,
      "dugByMe": false
    }
    """#

    // MARK: - list (paginated builder shape)

    func test_givenListFilters_whenBuilt_thenSetsPathQueryAuthAndPaginationKey() {
        // Given / When
        let request = Messages.list(limit: 10, offset: nil, onlyMine: true, tag: nil)

        // Then
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/messages")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertEqual(request.paginationKey, "messages")
        // Nil filters (offset, tag) are dropped by QueryItem's nil-skipping.
        let present = request.query.filter { $0.value != nil }
        XCTAssertEqual(present.count, 2)
        XCTAssertTrue(present.contains(QueryItem(name: "limit", value: "10")))
        XCTAssertTrue(present.contains(QueryItem(name: "onlyMine", value: "true")))
    }

    func test_givenMessagesEnvelope_whenDecodedWithPaginationKey_thenReturnsItemsAndPagination() throws {
        // Happy path: full envelope decodes via the builder's paginationKey.
        let request = Messages.list(limit: 2)
        let json = #"""
        {
          "messages": [ \#(messageJSON), \#(messageJSON) ],
          "pagination": { "total": 9, "limit": 2, "offset": 0, "hasMore": true }
        }
        """#

        let page = try PaginatedDecoder.decode(
            MessageDTO.self,
            collectionKey: try XCTUnwrap(request.paginationKey),
            from: Data(json.utf8)
        )

        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items.first?.id, "m1")
        XCTAssertEqual(page.items.first?.tags, ["swift", "macos"])
        XCTAssertEqual(page.pagination, PaginationInfo(total: 9, limit: 2, offset: 0, hasMore: true))
    }

    func test_givenEmptyMessagesEnvelope_whenDecoded_thenReturnsEmptyItems() throws {
        // Boundary: empty timeline.
        let json = #"{"messages":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}"#
        let page = try PaginatedDecoder.decode(
            MessageDTO.self,
            collectionKey: "messages",
            from: Data(json.utf8)
        )
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertFalse(page.pagination.hasMore)
    }

    // MARK: - get

    func test_givenMessageId_whenGetBuilt_thenTargetsThatMessage() {
        let request = Messages.get(id: "abc")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/messages/abc")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertNil(request.paginationKey)
    }

    func test_givenValidMessageResponse_whenGetSent_thenDecodesMessageDTO() async throws {
        // Happy path through the real client + transport.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(messageJSON))

        let message = try await client.send(Messages.get(id: "m1"))

        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(message.content, "Hello **world**")
        XCTAssertTrue(message.publiclyVisible)
        XCTAssertEqual(message.user.username, "ada")
        XCTAssertEqual(message.digCount, 3)
        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/messages/m1")
    }

    func test_givenNotFound_whenGetSent_thenThrowsNotFound() async throws {
        // Upstream API failure: 404.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Message not found"}"#, status: 404))

        do {
            _ = try await client.send(Messages.get(id: "missing"))
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Message not found"))
        }
    }

    func test_givenMalformedMessageBody_whenGetSent_thenThrowsDecoding() async throws {
        // Boundary / decode failure.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"id":"x"}"#))

        do {
            _ = try await client.send(Messages.get(id: "x"))
            XCTFail("Expected decoding failure")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenMessageWithNestedRepost_whenDecoded_thenDecodesPushedMessage() throws {
        // Happy path for the recursive pushedMessage box.
        let json = #"""
        {
          "id": "m2", "content": "repost", "publiclyVisible": true, "userId": "u2",
          "parentId": null, "linkMetadata": null, "imageUrls": null, "videoUrls": null,
          "crossPostUrls": null, "scheduledAt": null, "tags": null,
          "createdAt": "2026-06-16T12:00:00Z", "updatedAt": "2026-06-16T12:00:00Z",
          "digCount": 0, "pushCount": 0, "pushedMessageId": "m1",
          "user": { "id": "u2", "username": "grace", "displayName": null, "avatar": null },
          "pushedMessage": \#(messageJSON),
          "dugByMe": true
        }
        """#
        let decoded = try JSONCoders.makeDecoder().decode(MessageDTO.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.pushedMessageId, "m1")
        XCTAssertEqual(decoded.pushedMessage?.message.id, "m1")
        XCTAssertEqual(decoded.pushedMessage?.message.user.username, "ada")
    }

    // MARK: - create

    func test_givenPlainPost_whenCreateBuilt_thenPostsContentOnly() throws {
        // Happy path + boundary: optional fields omitted from the wire body.
        let request = Messages.create(CreateMessageRequest(content: "hi"))
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/messages")
        XCTAssertEqual(request.auth, .bearer)

        let body = try encodedBody(request)
        XCTAssertEqual(body["content"] as? String, "hi")
        XCTAssertNil(body["scheduledAt"])
        XCTAssertNil(body["crossPostToBluesky"])
        XCTAssertNil(body["tags"])
    }

    func test_givenCrossPostAndScheduled_whenCreateBuilt_thenEncodesAllSetFields() throws {
        // Happy path: the full M6 field set serializes correctly.
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let request = Messages.create(CreateMessageRequest(
            content: "scheduled post",
            publiclyVisible: false,
            tags: ["news"],
            parentId: nil,
            pushedMessageId: nil,
            scheduledAt: when,
            mastodonProviderIds: ["prov1", "prov2"],
            crossPostToBluesky: true,
            crossPostToLinkedIn: false
        ))

        let body = try encodedBody(request)
        XCTAssertEqual(body["content"] as? String, "scheduled post")
        XCTAssertEqual(body["publiclyVisible"] as? Bool, false)
        XCTAssertEqual(body["tags"] as? [String], ["news"])
        XCTAssertEqual(body["mastodonProviderIds"] as? [String], ["prov1", "prov2"])
        XCTAssertEqual(body["crossPostToBluesky"] as? Bool, true)
        XCTAssertEqual(body["crossPostToLinkedIn"] as? Bool, false)
        XCTAssertNotNil(body["scheduledAt"]) // ISO-8601 string emitted
        XCTAssertNil(body["parentId"])       // nil omitted
    }

    func test_givenValidPost_whenCreateSent_thenReturnsCreatedMessage() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(messageJSON, status: 201))

        let created = try await client.send(Messages.create(CreateMessageRequest(content: "hi")))
        XCTAssertEqual(created.id, "m1")
        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "POST")
        XCTAssertEqual(received[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test_givenServerRejectsPost_whenCreateSent_thenThrowsBadRequest() async throws {
        // Upstream API failure: 400 validation.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Content is required"}"#, status: 400))

        do {
            _ = try await client.send(Messages.create(CreateMessageRequest(content: "")))
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "Content is required"))
        }
    }

    // MARK: - update / delete

    func test_givenEdit_whenUpdateBuilt_thenPutsToMessagePath() throws {
        let request = Messages.update(id: "m1", CreateMessageRequest(content: "edited"))
        XCTAssertEqual(request.method, .put)
        XCTAssertEqual(request.path, "/api/messages/m1")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertEqual(try encodedBody(request)["content"] as? String, "edited")
    }

    func test_givenMessageId_whenDeleteBuilt_thenDeletesMessagePath() {
        let request = Messages.delete(id: "m1")
        XCTAssertEqual(request.method, .delete)
        XCTAssertEqual(request.path, "/api/messages/m1")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertNil(request.body)
    }

    func test_givenDeletableMessage_whenDeleteSent_thenSucceeds() async throws {
        // Boundary: 204 No Content.
        let (client, transport) = makeClient()
        await transport.enqueue(.empty(status: 204))
        try await client.sendVoid(Messages.delete(id: "m1"))
        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "DELETE")
    }

    func test_givenDeleteOnForeignMessage_whenSent_thenThrowsForbidden() async throws {
        // Upstream API failure: 403 not the author.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Not your message"}"#, status: 403))
        do {
            try await client.sendVoid(Messages.delete(id: "m1"))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "Not your message"))
        }
    }

    // MARK: - scheduled (non-standard envelope)

    func test_givenScheduled_whenBuilt_thenTargetsScheduledPath() {
        let request = Messages.scheduled()
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/messages/scheduled")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertNil(request.paginationKey) // not the standard envelope
    }

    func test_givenScheduledEnvelope_whenSent_thenDecodesMessagesArray() async throws {
        // Happy path: { "messages": [...] } with no pagination block.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"messages":[\#(messageJSON)]}"#))

        let response = try await client.send(Messages.scheduled())
        XCTAssertEqual(response.messages.count, 1)
        XCTAssertEqual(response.messages.first?.id, "m1")
    }

    func test_givenNoScheduledPosts_whenSent_thenDecodesEmptyArray() async throws {
        // Boundary: empty scheduled list.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"messages":[]}"#))
        let response = try await client.send(Messages.scheduled())
        XCTAssertTrue(response.messages.isEmpty)
    }

    func test_givenScheduledUnauthorized_whenSent_thenThrowsUnauthorized() async throws {
        // Upstream API failure: 401. Token store empty so the bearer header is
        // absent; the safety net's session retry also 401s (empty session
        // queue → cannotConnectToHost → transport), but the first 401 from a
        // bearer request triggers the retry. Use a token so the request is a
        // genuine bearer request and the session stub returns its own failure.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        do {
            _ = try await client.send(Messages.scheduled())
            XCTFail("Expected failure")
        } catch let error as APIError {
            // Either the original 401 or the session-retry transport failure is
            // acceptable; both are correct surfaced errors for this path.
            switch error {
            case .unauthorized, .transport:
                break
            default:
                XCTFail("Expected .unauthorized or .transport, got \(error)")
            }
        }
    }

    // MARK: - replies (non-standard envelope)

    func test_givenReplies_whenBuilt_thenTargetsRepliesPathWithPaging() {
        let request = Messages.replies(of: "m1", limit: 20, offset: 40)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/messages/m1/replies")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertNil(request.paginationKey) // non-standard { replies, total } envelope
        let present = request.query.filter { $0.value != nil }
        XCTAssertTrue(present.contains(QueryItem(name: "limit", value: "20")))
        XCTAssertTrue(present.contains(QueryItem(name: "offset", value: "40")))
    }

    func test_givenRepliesEnvelope_whenSent_thenDecodesRepliesAndTotal() async throws {
        // Happy path: { "replies": [...], "total": Int }.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"replies":[\#(messageJSON)],"total":1}"#))

        let response = try await client.send(Messages.replies(of: "m1"))
        XCTAssertEqual(response.total, 1)
        XCTAssertEqual(response.replies.first?.id, "m1")
    }

    func test_givenNoReplies_whenSent_thenDecodesEmptyWithZeroTotal() async throws {
        // Boundary: empty replies.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"replies":[],"total":0}"#))
        let response = try await client.send(Messages.replies(of: "m1"))
        XCTAssertTrue(response.replies.isEmpty)
        XCTAssertEqual(response.total, 0)
    }

    // MARK: - dig / undig

    func test_givenMessageId_whenDigBuilt_thenPostsToDigPath() {
        let request = Messages.dig(id: "m1")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/messages/m1/dig")
        XCTAssertEqual(request.auth, .bearer)
    }

    func test_givenMessageId_whenUndigBuilt_thenDeletesDigPath() {
        let request = Messages.undig(id: "m1")
        XCTAssertEqual(request.method, .delete)
        XCTAssertEqual(request.path, "/api/messages/m1/dig")
        XCTAssertEqual(request.auth, .bearer)
    }

    func test_givenDigResponse_whenDigSent_thenDecodesCountAndState() async throws {
        // Happy path: add-dig response carries isNewDig + digCreatedAt.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"digCount":5,"dugByMe":true,"isNewDig":true,"digCreatedAt":"2026-06-16T12:00:00.000Z"}"#))

        let response = try await client.send(Messages.dig(id: "m1"))
        XCTAssertEqual(response.digCount, 5)
        XCTAssertTrue(response.dugByMe)
        XCTAssertEqual(response.isNewDig, true)
        XCTAssertNotNil(response.digCreatedAt)
    }

    func test_givenUndigResponse_whenUndigSent_thenDecodesWithoutOptionalFields() async throws {
        // Boundary: remove-dig response omits isNewDig + digCreatedAt.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"digCount":4,"dugByMe":false,"isNewDig":false}"#))

        let response = try await client.send(Messages.undig(id: "m1"))
        XCTAssertEqual(response.digCount, 4)
        XCTAssertFalse(response.dugByMe)
        XCTAssertNil(response.digCreatedAt)
    }

    func test_givenDigOnMissingMessage_whenSent_thenThrowsNotFound() async throws {
        // Upstream API failure.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Message not found"}"#, status: 404))
        do {
            _ = try await client.send(Messages.dig(id: "ghost"))
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Message not found"))
        }
    }

    // MARK: - uploads (raw body)

    func test_givenImageBytes_whenUploadImageBuilt_thenUsesRawBodyAndContentType() {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let request = Messages.uploadImage(data, contentType: "image/png")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/messages/images/upload")
        XCTAssertEqual(request.auth, .bearer)
        guard case .raw(let bytes, let contentType) = request.body else {
            return XCTFail("Expected raw body")
        }
        XCTAssertEqual(bytes, data)
        XCTAssertEqual(contentType, "image/png")
    }

    func test_givenVideoBytes_whenUploadVideoBuilt_thenUsesRawBody() {
        let data = Data([0x00, 0x01])
        let request = Messages.uploadVideo(data, contentType: "video/mp4")
        XCTAssertEqual(request.path, "/api/messages/videos/upload")
        guard case .raw(_, let contentType) = request.body else {
            return XCTFail("Expected raw body")
        }
        XCTAssertEqual(contentType, "video/mp4")
    }

    func test_givenSuccessfulUpload_whenSent_thenDecodesURL() async throws {
        // Happy path: { "url": "..." } and the raw bytes reach the wire.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"url":"https://blob/x.png"}"#))

        let data = Data([0x89, 0x50])
        let response = try await client.send(Messages.uploadImage(data, contentType: "image/png"))
        XCTAssertEqual(response.url, "https://blob/x.png")
        let received = await transport.received
        XCTAssertEqual(received[0].value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(received[0].httpBody, data)
    }

    func test_givenOversizeUpload_whenSent_thenThrowsBadRequest() async throws {
        // Upstream API failure: media too large.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Image too large"}"#, status: 400))
        do {
            _ = try await client.send(Messages.uploadImage(Data([0x00]), contentType: "image/png"))
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "Image too large"))
        }
    }

    // MARK: - public user messages

    func test_givenUsername_whenUserMessagesBuilt_thenIsPublicNoAuthPaginated() {
        let request = Messages.userMessages(username: "ada", limit: 5, offset: nil)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/user/ada/messages")
        XCTAssertEqual(request.auth, .none) // public, no auth
        XCTAssertEqual(request.paginationKey, "messages")
        let present = request.query.filter { $0.value != nil }
        XCTAssertEqual(present.count, 1)
        XCTAssertTrue(present.contains(QueryItem(name: "limit", value: "5")))
    }

    func test_givenPublicMessagesEnvelope_whenDecoded_thenReturnsItems() throws {
        // Happy path: public endpoint uses the standard envelope.
        let request = Messages.userMessages(username: "ada")
        let json = #"{"messages":[\#(messageJSON)],"pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}"#
        let page = try PaginatedDecoder.decode(
            MessageDTO.self,
            collectionKey: try XCTUnwrap(request.paginationKey),
            from: Data(json.utf8)
        )
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.user.username, "ada")
    }
}

/// Local Encodable eraser so tests can serialize a `Request`'s JSON body
/// (which is stored as `any Encodable & Sendable`) through `JSONEncoder`.
private struct AnyEncodableProbe: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { self._encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
