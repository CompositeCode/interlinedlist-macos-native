import XCTest
@testable import InterlinedKit

/// BDD tests for the Moderation endpoint group (the-gaps.md G2).
final class ModerationEndpointTests: XCTestCase {

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

    func test_givenModerationBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Moderation.blocks().path, "/api/user/blocks")
        XCTAssertEqual(Moderation.blocks().method, .get)
        XCTAssertEqual(Moderation.mutes().path, "/api/user/mutes")

        XCTAssertEqual(Moderation.block(username: "ada").method, .post)
        XCTAssertEqual(Moderation.block(username: "ada").path, "/api/users/ada/block")
        XCTAssertEqual(Moderation.unblock(username: "ada").method, .delete)
        XCTAssertEqual(Moderation.unblock(username: "ada").path, "/api/users/ada/block")

        XCTAssertEqual(Moderation.mute(username: "ada").method, .post)
        XCTAssertEqual(Moderation.mute(username: "ada").path, "/api/users/ada/mute")
        XCTAssertEqual(Moderation.unmute(username: "ada").method, .delete)
        XCTAssertEqual(Moderation.unmute(username: "ada").path, "/api/users/ada/mute")

        XCTAssertEqual(Moderation.reportUser(username: "ada", reason: "spam").path, "/api/users/ada/report")
        XCTAssertEqual(Moderation.reportUser(username: "ada", reason: "spam").method, .post)
        XCTAssertEqual(Moderation.reportMessage(id: "m1", reason: "spam").path, "/api/messages/m1/report")
        XCTAssertEqual(Moderation.blocks().auth, .bearer)
    }

    // MARK: - Happy path (list decode)

    func test_givenBlocksBody_whenSent_thenDecodesUsersAndPagination() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"blockedUsers":[{"id":"u1","username":"spammer","displayName":"Spam Bot","avatar":"https://cdn/x.png"}],
         "pagination":{"total":1,"limit":20,"offset":0,"hasMore":false}}
        """#))

        let response = try await client.send(Moderation.blocks())

        XCTAssertEqual(response.blockedUsers.map(\.id), ["u1"])
        XCTAssertEqual(response.blockedUsers.first?.username, "spammer")
        XCTAssertEqual(response.pagination?.total, 1)
    }

    func test_givenMutesBody_whenSent_thenDecodesUsers() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"mutedUsers":[{"id":"u2"}],"pagination":{"total":1,"limit":20,"offset":0,"hasMore":false}}"#))

        let response = try await client.send(Moderation.mutes())

        XCTAssertEqual(response.mutedUsers.map(\.id), ["u2"])
        XCTAssertNil(response.mutedUsers.first?.username)
    }

    // MARK: - Report body encoding

    func test_givenReasonAndDetail_whenReportUserSent_thenEncodesReportBody() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"ok":true}"#))

        _ = try await client.send(Moderation.reportUser(username: "ada", reason: "harassment", detail: "context here"))

        let received = await transport.received
        let body = try XCTUnwrap(received[0].httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["reason"] as? String, "harassment")
        XCTAssertEqual(json?["detail"] as? String, "context here")
        XCTAssertEqual(received[0].httpMethod, "POST")
    }

    // MARK: - API failure

    func test_givenServerError_whenBlocksSent_thenThrowsHttpStatus() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"boom"}"#, status: 500))

        do {
            _ = try await client.send(Moderation.blocks())
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoBlocks_whenSent_thenReturnsEmptyList() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"blockedUsers":[],"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#))

        let response = try await client.send(Moderation.blocks())

        XCTAssertTrue(response.blockedUsers.isEmpty)
    }
}
