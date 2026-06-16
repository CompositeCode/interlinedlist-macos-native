import XCTest
@testable import InterlinedKit

/// BDD tests for the Follow / Social endpoint group.
final class FollowEndpointTests: XCTestCase {

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

    func test_givenFollowBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Follow.follow(userId: "u1").method, .post)
        XCTAssertEqual(Follow.follow(userId: "u1").path, "/api/follow/u1")
        XCTAssertEqual(Follow.follow(userId: "u1").auth, .bearer)

        XCTAssertEqual(Follow.unfollow(userId: "u1").method, .delete)
        XCTAssertEqual(Follow.status(userId: "u1").path, "/api/follow/u1/status")
        XCTAssertEqual(Follow.followers(userId: "u1").path, "/api/follow/u1/followers")
        XCTAssertEqual(Follow.following(userId: "u1").path, "/api/follow/u1/following")
        XCTAssertEqual(Follow.counts(userId: "u1").path, "/api/follow/u1/counts")
        XCTAssertEqual(Follow.mutual(userId: "u1").path, "/api/follow/u1/mutual")

        XCTAssertEqual(Follow.approve(userId: "u1").method, .post)
        XCTAssertEqual(Follow.approve(userId: "u1").path, "/api/follow/u1/approve")
        XCTAssertEqual(Follow.reject(userId: "u1").path, "/api/follow/u1/reject")
        XCTAssertEqual(Follow.remove(userId: "u1").path, "/api/follow/u1/remove")

        XCTAssertEqual(Follow.requests().path, "/api/follow/requests")
        XCTAssertEqual(Follow.requests().method, .get)
        XCTAssertEqual(Follow.requests().paginationKey, "data")
    }

    // MARK: - Happy path

    func test_givenStatusBody_whenStatusSent_thenDecodesRelationshipFlags() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"following":true,"followedBy":false,"pendingRequest":false}"#))

        let status = try await client.send(Follow.status(userId: "u1"))

        XCTAssertTrue(status.following)
        XCTAssertFalse(status.followedBy)
        XCTAssertFalse(status.pendingRequest)

        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/follow/u1/status")
        XCTAssertEqual(received[0].value(forHTTPHeaderField: "Authorization"), "Bearer il_tok_abc")
    }

    func test_givenCountsBody_whenCountsSent_thenDecodesCounts() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"followerCount":42,"followingCount":7}"#))

        let counts = try await client.send(Follow.counts(userId: "u1"))

        XCTAssertEqual(counts.followerCount, 42)
        XCTAssertEqual(counts.followingCount, 7)
    }

    func test_givenFollowerArray_whenFollowersSent_thenDecodesUserArray() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"[{"id":"a","username":"ada"},{"id":"b","username":"bob"}]"#))

        let users = try await client.send(Follow.followers(userId: "u1"))

        XCTAssertEqual(users.map(\.id), ["a", "b"])
        XCTAssertEqual(users.first?.username, "ada")
    }

    func test_givenSuccessEnvelope_whenFollowSent_thenDecodesActionResponse() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"success":true}"#))

        let result = try await client.send(Follow.follow(userId: "u1"))

        XCTAssertEqual(result.success, true)
        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "POST")
    }

    // MARK: - API failure

    func test_givenUnauthorized_whenStatusSent_thenThrowsUnauthorized() async throws {
        // Bearer 401 with no token store entry triggers the safety-net retry;
        // the session transport here is empty and also fails, surfacing 401.
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        await base.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        await session.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))

        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(),
            sessionTransport: session,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: base, authTransport: auth)

        do {
            _ = try await client.send(Follow.status(userId: "u1"))
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "Unauthorized"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenEmptyFollowerArray_whenFollowersSent_thenReturnsNoUsers() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json("[]"))

        let users = try await client.send(Follow.followers(userId: "u1"))

        XCTAssertTrue(users.isEmpty)
    }

    func test_givenEmptyRequestsEnvelope_whenRequestsSent_thenReturnsNoItems() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"data":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(FollowRequestDTO.self, request: Follow.requests(), using: client)

        XCTAssertTrue(page.items.isEmpty)
    }

    func test_givenMutualWithoutUsers_whenMutualSent_thenDecodesTolerantly() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"count":0}"#))

        let mutual = try await client.send(Follow.mutual(userId: "u1"))

        XCTAssertEqual(mutual.count, 0)
        XCTAssertNil(mutual.mutual)
    }
}
