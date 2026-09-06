import XCTest
@testable import InterlinedKit

/// BDD tests for the **G27 small, self-contained gaps** — four one-off routes
/// the client did not reach, all probed live on 2026-09-06 before being built.
///
/// | Route                                  | Live `Allow`                                 | Notes                              |
/// | -------------------------------------- | -------------------------------------------- | ---------------------------------- |
/// | `DELETE /api/notifications/{id}`       | `DELETE, OPTIONS`                            | 204, no body                       |
/// | `POST /api/messages/{id}/reply-counts` | `OPTIONS, POST`                              | `{replyCounts, repliesCheckedAt}`  |
/// | `GET /api/user/engagement`             | `GET, HEAD, OPTIONS`                         | **session-only** — 401 on Bearer   |
/// | `PUT /api/documents/{id}`              | `DELETE, GET, HEAD, OPTIONS, PATCH, PUT`     | full replace beside `PATCH`        |
final class SmallGapEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        sessionTransport: StubHTTPDataTransport = StubHTTPDataTransport()
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_abc"),
            sessionTransport: sessionTransport,
            sessionEstablisher: NullSessionEstablisher()
        )
        return (APIClient(baseURL: baseURL, transport: transport, authTransport: auth), transport)
    }

    // MARK: - Builder shapes

    func test_givenSmallGapBuilders_whenConstructed_thenUseTheLiveVerbPathAndAuth() {
        let notification = Notifications.delete(id: "n1")
        XCTAssertEqual(notification.method, .delete)
        XCTAssertEqual(notification.path, "/api/notifications/n1")
        XCTAssertEqual(notification.auth, .bearer)

        let replyCounts = Messages.refreshReplyCounts(id: "m1")
        XCTAssertEqual(replyCounts.method, .post)
        XCTAssertEqual(replyCounts.path, "/api/messages/m1/reply-counts")
        XCTAssertEqual(replyCounts.auth, .bearer)

        let replace = Documents.replace(id: "d1", UpdateDocumentRequest(title: "T"))
        XCTAssertEqual(replace.method, .put)
        XCTAssertEqual(replace.path, "/api/documents/d1")
        XCTAssertEqual(replace.auth, .bearer)
    }

    /// Engagement is the one that is **not** `.bearer`. A regression to bearer
    /// would 401 against production, which is exactly how it was mis-recorded
    /// as "may be session-only, confirm before building".
    func test_givenEngagementBuilder_whenConstructed_thenUsesSessionAuth() {
        let request = User.engagement()
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/user/engagement")
        XCTAssertEqual(request.auth, .session, "engagement 401s under Bearer — it must use the cookie session")
    }

    // MARK: - Happy path

    func test_givenReplyCountEnvelope_whenRefreshSent_thenDecodesPerPlatformRows() async throws {
        let (client, transport) = makeClient()
        // The real 2026-09-06 body.
        await transport.enqueue(.json(#"""
        {"replyCounts":[
           {"platform":"mastodon","count":0,"status":"success","checkedAt":"2026-09-06T06:59:29.004Z"},
           {"platform":"bluesky","count":3,"status":"success","checkedAt":"2026-09-06T06:59:29.005Z"},
           {"platform":"twitter","status":"unsupported","checkedAt":"2026-09-06T06:59:29.132Z"}],
         "repliesCheckedAt":"2026-09-06T06:59:28.751Z"}
        """#))

        let response = try await client.send(Messages.refreshReplyCounts(id: "m1"))

        XCTAssertEqual(response.replyCounts.map(\.platform), ["mastodon", "bluesky", "twitter"])
        XCTAssertEqual(response.replyCounts[1].count, 3)
        XCTAssertNotNil(response.repliesCheckedAt)
    }

    /// Boundary: an unsupported platform reports no `count` at all. It must
    /// decode as `nil`, never as a misleading `0`.
    func test_givenUnsupportedPlatform_whenRefreshSent_thenCountIsNilNotZero() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"replyCounts":[{"platform":"twitter","status":"unsupported","checkedAt":"2026-09-06T06:59:29.132Z"}],
         "repliesCheckedAt":null}
        """#))

        let response = try await client.send(Messages.refreshReplyCounts(id: "m1"))

        XCTAssertNil(response.replyCounts.first?.count)
        XCTAssertEqual(response.replyCounts.first?.status, "unsupported")
        XCTAssertNil(response.repliesCheckedAt)
    }

    func test_givenEngagementEnvelope_whenSent_thenDecodesTotalsAndRecent() async throws {
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"""
        {"totalDigs":24,"totalPushes":6,
         "recent":[{"id":"n1","title":"Pushed — Adron Hall (@adron)","body":"Your message: …",
           "type":"push","sourceMessageId":"m1","createdAt":"2026-09-01T00:00:00.000Z",
           "routePath":"/messages/m1"}]}
        """#))
        let (client, _) = makeClient(sessionTransport: session)

        let response = try await client.send(User.engagement())

        XCTAssertEqual(response.totalDigs, 24)
        XCTAssertEqual(response.totalPushes, 6)
        XCTAssertEqual(response.recent.first?.sourceMessageId, "m1")
    }

    func test_givenDocumentEnvelope_whenReplaceSent_thenDecodesUnderDocumentKey() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"message":"Document updated successfully",
         "document":{"id":"d1","title":"Replaced","content":"new body"}}
        """#))

        let response = try await client.send(
            Documents.replace(id: "d1", UpdateDocumentRequest(title: "Replaced", content: "new body"))
        )

        XCTAssertEqual(response.document.title, "Replaced")
        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "PUT")
    }

    // MARK: - Boundary

    /// The notification delete answers 204 with no body, so it must go through
    /// `sendVoid` without a decode step.
    func test_givenNoContent_whenNotificationDeleteSent_thenSucceeds() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.empty(status: 204))

        try await client.sendVoid(Notifications.delete(id: "n1"))

        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "DELETE")
        XCTAssertEqual(received[0].url?.path, "/api/notifications/n1")
    }

    /// Boundary: zero totals and an empty feed are a legitimate fresh account,
    /// not a decode failure.
    func test_givenEmptyEngagement_whenSent_thenDecodesZeroTotals() async throws {
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"{"totalDigs":0,"totalPushes":0,"recent":[]}"#))
        let (client, _) = makeClient(sessionTransport: session)

        let response = try await client.send(User.engagement())

        XCTAssertEqual(response.totalDigs, 0)
        XCTAssertTrue(response.recent.isEmpty)
    }

    // MARK: - Upstream failure

    func test_givenMissingNotification_whenDeleteSent_thenThrowsNotFound() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Not found"}"#, status: 404))

        do {
            try await client.sendVoid(Notifications.delete(id: "gone"))
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Not found"))
        }
    }

    /// The failure the live route produces when the bearer token is used
    /// instead of the session — the reason `engagement()` is `.session`.
    func test_givenUnauthorized_whenEngagementSent_thenThrowsUnauthorized() async throws {
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"{"error":"Unauthorized","code":"unauthorized"}"#, status: 401))
        let (client, _) = makeClient(sessionTransport: session)

        do {
            _ = try await client.send(User.engagement())
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "Unauthorized"))
        }
    }
}
