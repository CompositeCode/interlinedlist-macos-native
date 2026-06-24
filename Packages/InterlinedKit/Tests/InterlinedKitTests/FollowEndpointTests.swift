import XCTest
@testable import InterlinedKit

/// BDD tests for the Follow / Social endpoint group.
///
/// Envelope shapes verified against the live API on 2026-06-24:
/// - `/api/follow/[id]/followers` → `{ followers: [...], pagination: {...} }`
/// - `/api/follow/[id]/following` → `{ following: [...], pagination: {...} }`
/// - `/api/follow/[id]/mutual` → `{ mutualFollowers, mutualFollowing }` (counts only)
/// - `/api/follow/requests` → `{ requests: [...] }` (no pagination today)
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
        XCTAssertEqual(Follow.followers(userId: "u1").paginationKey, "followers")
        XCTAssertEqual(Follow.following(userId: "u1").path, "/api/follow/u1/following")
        XCTAssertEqual(Follow.following(userId: "u1").paginationKey, "following")
        XCTAssertEqual(Follow.counts(userId: "u1").path, "/api/follow/u1/counts")
        XCTAssertEqual(Follow.mutual(userId: "u1").path, "/api/follow/u1/mutual")

        XCTAssertEqual(Follow.approve(userId: "u1").method, .post)
        XCTAssertEqual(Follow.approve(userId: "u1").path, "/api/follow/u1/approve")
        XCTAssertEqual(Follow.reject(userId: "u1").path, "/api/follow/u1/reject")
        XCTAssertEqual(Follow.remove(userId: "u1").path, "/api/follow/u1/remove")

        XCTAssertEqual(Follow.requests().path, "/api/follow/requests")
        XCTAssertEqual(Follow.requests().method, .get)
        XCTAssertNil(Follow.requests().paginationKey)
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

    func test_givenFollowersEnvelope_whenDecoded_thenReturnsPaginatedUsers() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {
          "followers": [
            {"id":"a","username":"ada","displayName":"Ada","avatar":"https://x/a.png","followId":"f1","status":"approved"},
            {"id":"b","username":"bob","displayName":null,"avatar":null,"followId":"f2","status":"approved"}
          ],
          "pagination": {"total":2,"limit":50,"offset":0,"hasMore":false}
        }
        """#))

        let page = try await fetchPaginated(
            FollowUserDTO.self,
            request: Follow.followers(userId: "u1"),
            using: client
        )

        XCTAssertEqual(page.items.map(\.id), ["a", "b"])
        XCTAssertEqual(page.items.first?.username, "ada")
        XCTAssertEqual(page.items.first?.avatar, "https://x/a.png")
        XCTAssertEqual(page.items.first?.status, "approved")
        XCTAssertEqual(page.items.first?.followId, "f1")
        XCTAssertEqual(page.pagination.total, 2)
        XCTAssertFalse(page.pagination.hasMore)
    }

    func test_givenFollowingEnvelope_whenDecoded_thenReturnsPaginatedUsers() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {
          "following": [
            {"id":"c","username":"cas","followId":"f3","status":"pending"}
          ],
          "pagination": {"total":17,"limit":50,"offset":0,"hasMore":true}
        }
        """#))

        let page = try await fetchPaginated(
            FollowUserDTO.self,
            request: Follow.following(userId: "u2"),
            using: client
        )

        XCTAssertEqual(page.items.map(\.id), ["c"])
        XCTAssertEqual(page.items.first?.status, "pending")
        XCTAssertEqual(page.pagination.total, 17)
        XCTAssertTrue(page.pagination.hasMore)
    }

    func test_givenFollowersBuilderWithQueryParams_whenInspected_thenIncludesLimitOffsetStatus() {
        let req = Follow.followers(userId: "u1", limit: 10, offset: 20, status: "approved")
        let names = req.query.map(\.name).sorted()
        XCTAssertEqual(names, ["limit", "offset", "status"])
    }

    func test_givenMutualBody_whenMutualSent_thenDecodesCountsOnly() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"mutualFollowers":12,"mutualFollowing":5}"#))

        let mutual = try await client.send(Follow.mutual(userId: "u1"))

        XCTAssertEqual(mutual.mutualFollowers, 12)
        XCTAssertEqual(mutual.mutualFollowing, 5)
    }

    func test_givenRequestsEnvelope_whenRequestsSent_thenDecodesList() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {
          "requests": [
            {"id":"r1","username":"alex","followId":"fr1"}
          ]
        }
        """#))

        let response = try await client.send(Follow.requests())

        XCTAssertEqual(response.requests.map(\.id), ["r1"])
        XCTAssertEqual(response.requests.first?.username, "alex")
        XCTAssertEqual(response.requests.first?.followId, "fr1")
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

    func test_givenEmptyFollowersEnvelope_whenDecoded_thenReturnsNoUsers() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"followers":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(
            FollowUserDTO.self,
            request: Follow.followers(userId: "u1"),
            using: client
        )

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.pagination.total, 0)
    }

    func test_givenEmptyRequestsEnvelope_whenRequestsSent_thenReturnsNoItems() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"requests":[]}"#))

        let response = try await client.send(Follow.requests())

        XCTAssertTrue(response.requests.isEmpty)
    }
}
