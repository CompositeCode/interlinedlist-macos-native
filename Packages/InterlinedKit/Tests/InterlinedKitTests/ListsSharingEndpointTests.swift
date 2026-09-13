import XCTest
@testable import InterlinedKit

/// BDD tests for the five Lists routes work-consolidation.md G23 (issue #48)
/// adds — the "lists other people gave me access to" story — plus the decode
/// corrections G23 recon turned up on the existing watcher routes.
///
/// Every shape asserted here was verified against the live API on 2026-09-09
/// with read-only probes (`GET` / `OPTIONS` only), or comes from
/// `/help/api/lists` and `/help/api/sharing` where the route is a write the
/// recon pass deliberately did not exercise.
final class ListsSharingEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_abc")
    ) -> (APIClient, StubHTTPDataTransport) {
        // The same stub backs the session transport so the decision-0001 401
        // safety net (which retries once over the session) reads from one
        // queue — otherwise a 401 test surfaces a transport error from the
        // empty second stub instead of the 401 under test.
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: transport,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    // MARK: - Builder shape

    func test_givenG23Builders_whenConstructed_thenUseExpectedMethodPathAuth() {
        // watching — Bearer, paginated under "lists".
        XCTAssertEqual(Lists.watching().method, .get)
        XCTAssertEqual(Lists.watching().path, "/api/lists/watching")
        XCTAssertEqual(Lists.watching().auth, .bearer)
        XCTAssertEqual(Lists.watching().paginationKey, "lists")

        // contributors — Bearer, unpaged.
        XCTAssertEqual(Lists.contributors(listId: "7").method, .get)
        XCTAssertEqual(Lists.contributors(listId: "7").path, "/api/lists/7/contributors")
        XCTAssertEqual(Lists.contributors(listId: "7").auth, .bearer)
        XCTAssertNil(Lists.contributors(listId: "7").paginationKey)

        // addWatcher — Bearer POST with a body.
        let add = Lists.addWatcher(listId: "7", AddListWatcherRequest(userId: "u2", role: "collaborator", notify: false))
        XCTAssertEqual(add.method, .post)
        XCTAssertEqual(add.path, "/api/lists/7/watchers")
        XCTAssertEqual(add.auth, .bearer)
        XCTAssertNotNil(add.body)

        // sharedRows — the token IS the capability, so no auth at all.
        XCTAssertEqual(Lists.sharedRows(token: "tok").method, .get)
        XCTAssertEqual(Lists.sharedRows(token: "tok").path, "/api/lists/shared/tok/data")
        XCTAssertEqual(Lists.sharedRows(token: "tok").auth, .none)
        XCTAssertEqual(Lists.sharedRows(token: "tok").paginationKey, "rows")

        // invite landing — public.
        XCTAssertEqual(Lists.invite(token: "tok").method, .get)
        XCTAssertEqual(Lists.invite(token: "tok").path, "/api/lists/invite/tok")
        XCTAssertEqual(Lists.invite(token: "tok").auth, .none)
    }

    func test_givenOptionalQuery_whenG23BuildersBuilt_thenSkipsNilParameters() {
        // Boundary: nil query parameters are dropped, not sent empty.
        let watching = Lists.watching(limit: 10, offset: nil, page: nil)
        XCTAssertEqual(Set(watching.query.compactMap { $0.value != nil ? $0.name : nil }), ["limit"])

        let rows = Lists.sharedRows(token: "tok", limit: nil, offset: 40)
        XCTAssertEqual(Set(rows.query.compactMap { $0.value != nil ? $0.name : nil }), ["offset"])

        // `excludeWatchers` is deliberately never sent: omitting it makes the
        // server auto-exclude the list's current watchers.
        let candidates = Lists.watcherCandidates(listId: "7", search: nil, limit: nil, offset: nil)
        XCTAssertTrue(candidates.query.allSatisfy { $0.value == nil })
    }

    // MARK: - watching round-trip

    func test_givenSharedLists_whenFetchingWatching_thenDecodesRoleOwnerAndParent() async throws {
        // Given — the exact live envelope (2026-09-09), trimmed to two rows.
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"lists":[
          {"id":"l-1","userId":"c65","messageId":null,"parentId":"p-1","folderId":null,
           "title":"Shows Upcoming & Seen","description":null,"isPublic":true,"metadata":null,
           "source":"local","githubRepo":null,"githubRepoPrivate":null,
           "createdAt":"2026-03-21T22:48:20.897Z","updatedAt":"2026-07-11T04:54:54.332Z","deletedAt":null,
           "user":{"id":"c65","username":"adron","displayName":"Adron Hall"},
           "parent":{"id":"p-1","title":"The Metal"},"children":[],"role":"collaborator"},
          {"id":"l-2","userId":"c65","parentId":null,"folderId":null,
           "title":"Videos to Watch","description":null,"isPublic":true,
           "createdAt":"2026-03-21T22:48:20.897Z","updatedAt":"2026-07-11T04:54:54.332Z",
           "user":{"id":"c65","username":"adron","displayName":"Adron Hall"},
           "parent":null,"children":[],"role":"watcher"}
        ],"pagination":{"total":2,"limit":50,"offset":0,"hasMore":false}}
        """, status: 200))

        // When
        let (data, _) = try await client.sendRaw(Lists.watching())
        let page = try PaginatedDecoder.decode(
            ListDTO.self,
            collectionKey: "lists",
            from: data,
            decoder: JSONCoders.makeDecoder()
        )

        // Then
        XCTAssertEqual(page.items.map(\.id), ["l-1", "l-2"])
        XCTAssertEqual(page.items.map(\.role), ["collaborator", "watcher"])
        XCTAssertEqual(page.items.first?.user?.username, "adron")
        XCTAssertEqual(page.items.first?.parent?.title, "The Metal")
        XCTAssertEqual(page.items.first?.userId, "c65")
        XCTAssertNil(page.items.last?.parent)
        XCTAssertFalse(page.pagination.hasMore)
    }

    func test_givenNothingShared_whenFetchingWatching_thenDecodesEmptyPage() async throws {
        // Boundary: an account nobody has shared with.
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"lists":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}
        """, status: 200))

        let (data, _) = try await client.sendRaw(Lists.watching())
        let page = try PaginatedDecoder.decode(
            ListDTO.self,
            collectionKey: "lists",
            from: data,
            decoder: JSONCoders.makeDecoder()
        )

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertFalse(page.pagination.hasMore)
    }

    func test_givenUnauthorizedCaller_whenFetchingWatching_thenThrowsUnauthorized() async throws {
        // Upstream-failure: the spec declares 401 as the only failure mode.
        let (client, transport) = makeClient()
        // Two: the safety net retries a Bearer 401 once over the session
        // transport before surfacing the status.
        await transport.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        await transport.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))

        do {
            _ = try await client.sendRaw(Lists.watching())
            XCTFail("Expected APIError.unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 401)
        }
    }

    // MARK: - contributors round-trip

    func test_givenRankedContributors_whenFetching_thenDecodesCountsAndScore() async throws {
        // Given — the exact live payload (2026-09-09).
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"contributors":[{"id":"c65","username":"adron","displayName":"Adron Hall",
          "avatar":"https://cdn.example/a.jpg","addedCount":17,"editedCount":17,"score":34}],
         "totalContributors":1}
        """, status: 200))

        let response = try await client.send(Lists.contributors(listId: "l-1"))

        XCTAssertEqual(response.totalContributors, 1)
        XCTAssertEqual(response.contributors.first?.username, "adron")
        XCTAssertEqual(response.contributors.first?.addedCount, 17)
        XCTAssertEqual(response.contributors.first?.score, 34)
    }

    func test_givenNoContributors_whenFetching_thenDecodesEmptyList() async throws {
        // Boundary: verified live against a brand-new list.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"contributors":[],"totalContributors":0}"#, status: 200))

        let response = try await client.send(Lists.contributors(listId: "l-1"))

        XCTAssertTrue(response.contributors.isEmpty)
        XCTAssertEqual(response.totalContributors, 0)
    }

    // MARK: - addWatcher

    func test_givenNamedUser_whenAddingWatcher_thenSendsUserIdRoleAndNotify() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"watching":true}"#, status: 201))

        let response = try await client.send(
            Lists.addWatcher(listId: "l-1", AddListWatcherRequest(userId: "u-9", role: "collaborator", notify: false))
        )

        XCTAssertEqual(response.watching, true)
        let sent = await transport.received
        XCTAssertEqual(sent.last?.httpMethod, "POST")
        XCTAssertEqual(sent.last?.url?.path, "/api/lists/l-1/watchers")
        let body = try XCTUnwrap(sent.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["userId"] as? String, "u-9")
        XCTAssertEqual(json["role"] as? String, "collaborator")
        XCTAssertEqual(json["notify"] as? Bool, false)
    }

    func test_givenFreeOwner_whenAddingWatcher_thenThrowsForbidden() async throws {
        // Upstream-failure: the documented subscriber gate.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Subscribe to share lists."}"#, status: 403))

        do {
            _ = try await client.send(
                Lists.addWatcher(listId: "l-1", AddListWatcherRequest(userId: "u-9"))
            )
            XCTFail("Expected APIError.forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 403)
        }
    }

    func test_givenSelfSubscribeBody_whenEncoded_thenOmitsUserId() throws {
        // Boundary: the documented second mode of the same route — no
        // `userId` means "watch this list myself", which is free.
        let data = try JSONCoders.makeEncoder().encode(AddListWatcherRequest())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["userId"])
        XCTAssertNil(json["role"])
    }

    // MARK: - shared row data

    func test_givenValidShareToken_whenFetchingSharedRows_thenDecodesRowsEnvelope() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"rows":[{"id":"r-1","listId":"l-1","rowData":{"bands":"Igorrr","date":"2026-09-28"},
          "createdAt":"2026-07-12T03:58:54.991Z","updatedAt":"2026-07-12T03:58:54.991Z"}],
         "pagination":{"total":17,"limit":1,"offset":0,"hasMore":true}}
        """, status: 200))

        let (data, _) = try await client.sendRaw(Lists.sharedRows(token: "tok", limit: 1))
        let page = try PaginatedDecoder.decode(
            ListRowDTO.self,
            collectionKey: "rows",
            from: data,
            decoder: JSONCoders.makeDecoder()
        )

        XCTAssertEqual(page.items.map(\.id), ["r-1"])
        XCTAssertEqual(page.items.first?.rowData["bands"]?.stringValue, "Igorrr")
        XCTAssertTrue(page.pagination.hasMore)
    }

    func test_givenSharedRowsRequest_whenBuilt_thenCarriesNoAuthorizationHeader() async throws {
        // The token is the capability; sending a Bearer would be pointless and
        // would leak the caller's identity to a public route.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"rows":[],"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#, status: 200))

        _ = try await client.sendRaw(Lists.sharedRows(token: "tok"))

        let sent = await transport.received
        XCTAssertNil(sent.last?.value(forHTTPHeaderField: "Authorization"))
    }

    func test_givenRevokedShareToken_whenFetchingSharedRows_thenThrowsNotFound() async throws {
        // Upstream-failure, verified live: unknown / expired / revoked are one
        // deliberately indistinguishable 404.
        let (client, transport) = makeClient()
        await transport.enqueue(
            .json(#"{"error":"Share link not found, expired, or revoked","code":"not_found"}"#, status: 404)
        )

        do {
            _ = try await client.sendRaw(Lists.sharedRows(token: "gone"))
            XCTFail("Expected APIError.notFound")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 404)
        }
    }

    // MARK: - invite landing

    func test_givenClaimableInvite_whenResolving_thenDecodesEveryFlag() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"role":"collaborator","needsAuth":false,"canClaim":true,
         "wrongAccount":false,"accepted":false,"resourceTitle":"Q3 Planning"}
        """, status: 200))

        let dto = try await client.send(Lists.invite(token: "tok"))

        XCTAssertEqual(dto.role, "collaborator")
        XCTAssertEqual(dto.canClaim, true)
        XCTAssertEqual(dto.needsAuth, false)
        XCTAssertEqual(dto.wrongAccount, false)
        XCTAssertEqual(dto.accepted, false)
        XCTAssertEqual(dto.resourceTitle, "Q3 Planning")
    }

    func test_givenAnonymousCaller_whenResolvingInvite_thenTolerateOmittedFlags() async throws {
        // Boundary: an anonymous resolve returns less. Every field is optional
        // so the landing still renders instead of failing at the decoder.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"role":"watcher","needsAuth":true}"#, status: 200))

        let dto = try await client.send(Lists.invite(token: "tok"))

        XCTAssertEqual(dto.role, "watcher")
        XCTAssertEqual(dto.needsAuth, true)
        XCTAssertNil(dto.canClaim)
        XCTAssertNil(dto.resourceTitle)
    }

    func test_givenExpiredInvite_whenResolving_thenThrowsNotFound() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(
            .json(#"{"error":"Invite not found, expired, or revoked","code":"not_found"}"#, status: 404)
        )

        do {
            _ = try await client.send(Lists.invite(token: "gone"))
            XCTFail("Expected APIError.notFound")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 404)
        }
    }

    // MARK: - Watcher-route decode corrections (G23 recon)

    func test_givenWatchersEnvelope_whenDecoded_thenReadsNestedUser() async throws {
        // Regression: the route answers `{ watchers: [...] }`, not a bare
        // array, and nests the person under `user`.
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"watchers":[{"id":"w-1","userId":"u-1","role":"collaborator",
          "createdAt":"2026-06-16T12:00:00Z",
          "user":{"id":"u-1","username":"ada","displayName":"Ada Lovelace","avatar":null}}],
         "pagination":{"total":1,"limit":20,"offset":0,"hasMore":false}}
        """, status: 200))

        let response = try await client.send(Lists.watchers(listId: "l-1"))

        XCTAssertEqual(response.watchers.map(\.userId), ["u-1"])
        XCTAssertEqual(response.watchers.first?.user?.username, "ada")
        XCTAssertEqual(response.watchers.first?.id, "w-1")
    }

    func test_givenWatcherStatus_whenDecoded_thenReadsWatchingKey() async throws {
        // Regression: the wire key is `watching`, not `isWatching`.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"watching":true,"role":"collaborator"}"#, status: 200))

        let dto = try await client.send(Lists.myWatcherStatus(listId: "l-1"))

        XCTAssertEqual(dto.isWatching, true)
        XCTAssertEqual(dto.role, "collaborator")
    }

    func test_givenCandidateSearch_whenDecoded_thenReadsUsersEnvelope() async throws {
        // Regression: `/watchers/users` returns people, not watcher rows.
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"users":[{"id":"u-9","username":"Ajdixa","displayName":"Someone",
                   "email":"a@example.com","avatar":null}],
         "total":18,"pagination":{"limit":1,"offset":0,"hasMore":true}}
        """, status: 200))

        let response = try await client.send(Lists.watcherCandidates(listId: "l-1", search: "aj", limit: 1))

        XCTAssertEqual(response.users.map(\.id), ["u-9"])
        XCTAssertEqual(response.users.first?.email, "a@example.com")
        XCTAssertEqual(response.total, 18)
    }

    func test_givenRoleChangeResponse_whenDecoded_thenReadsRoleOnly() async throws {
        // Regression: the PUT answers `{ role }`, not the watcher row.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"role":"manager"}"#, status: 200))

        let response = try await client.send(
            Lists.setWatcher(listId: "l-1", userId: "u-9", UpdateListWatcherRequest(role: "manager", notify: false))
        )

        XCTAssertEqual(response.role, "manager")
    }
}
