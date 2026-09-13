import XCTest
@testable import InterlinedKit

/// BDD tests for the Organizations endpoint group.
final class OrganizationsEndpointTests: XCTestCase {

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

    func test_givenOrgBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Organizations.list().path, "/api/organizations")
        XCTAssertEqual(Organizations.list().auth, .bearer)
        XCTAssertEqual(Organizations.list().paginationKey, "data")

        XCTAssertEqual(Organizations.create(CreateOrganizationRequest(name: "Acme", description: "d", isPublic: true)).method, .post)
        XCTAssertEqual(Organizations.get(id: "o1").path, "/api/organizations/o1")
        // PUT, not PATCH — PATCH is 405 live (work-consolidation.md §1c · V4).
        XCTAssertEqual(Organizations.update(id: "o1", UpdateOrganizationRequest(name: "x")).method, .put)

        XCTAssertEqual(Organizations.members(id: "o1").path, "/api/organizations/o1/members")
        XCTAssertEqual(Organizations.members(id: "o1").paginationKey, "members")
        XCTAssertEqual(Organizations.addMember(id: "o1", AddOrganizationMemberRequest(userId: "u2", role: "member")).method, .post)
        XCTAssertEqual(Organizations.updateMember(id: "o1", userId: "u2", UpdateOrganizationMemberRequest(role: "admin")).method, .put)
        XCTAssertEqual(Organizations.updateMember(id: "o1", userId: "u2", UpdateOrganizationMemberRequest(role: "admin")).path, "/api/organizations/o1/members/u2")
        XCTAssertEqual(Organizations.removeMember(id: "o1", userId: "u2").method, .delete)
        XCTAssertEqual(Organizations.users(id: "o1").path, "/api/organizations/o1/users")
    }

    func test_givenFilters_whenListBuilt_thenSkipsNilQueryParameters() {
        let req = Organizations.list(isPublic: true, userId: nil)
        let names = req.query.compactMap { $0.value != nil ? $0.name : nil }
        XCTAssertEqual(Set(names), ["public"])
    }

    // MARK: - Happy path

    func test_givenOrgEnvelope_whenListSent_thenDecodesUnderDataKey() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"data":[{"id":"o1","name":"Acme","isPublic":true}],
         "pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(OrganizationDTO.self, request: Organizations.list(), using: client)

        XCTAssertEqual(page.items.first?.name, "Acme")
        XCTAssertEqual(page.items.first?.isPublic, true)
    }

    func test_givenLiveMembersEnvelope_whenMembersSent_thenDecodesIdentityKeyedById() async throws {
        // Happy path against the **real** members body, captured live
        // 2026-09-09. The row is keyed by `id` (not `userId`), dated with
        // `joinedAt` (not `createdAt`), and carries the member's identity.
        //
        // This is a regression test for a shipped decode defect: the DTO
        // declared `userId: String` as required, so every real members
        // response failed with `keyNotFound(userId)` and the roster never
        // rendered.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"members":[
          {"id":"c65092fa","username":"adron","displayName":"Adron Hall",
           "avatar":"https://cdn.example/a.jpg","emailVerified":true,
           "role":"owner","active":true,"joinedAt":"2026-02-22T19:38:07.993Z"},
          {"id":"72a147f7","username":"hubcity","displayName":"HubCity",
           "avatar":"","emailVerified":true,
           "role":"member","active":true,"joinedAt":"2026-03-24T02:39:02.349Z"}],
         "pagination":{"total":2,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(OrganizationMemberDTO.self, request: Organizations.members(id: "o1"), using: client)

        XCTAssertEqual(page.items.map(\.userId), ["c65092fa", "72a147f7"])
        XCTAssertEqual(page.items.map(\.role), ["owner", "member"])
        XCTAssertEqual(page.items.first?.active, true)
        XCTAssertEqual(page.items.first?.displayName, "Adron Hall")
        XCTAssertEqual(page.items.first?.username, "adron")
        XCTAssertEqual(page.items.first?.emailVerified, true)
        XCTAssertNotNil(page.items.first?.createdAt, "joinedAt maps onto createdAt")
    }

    func test_givenDocumentedUserIdSpelling_whenMembersSent_thenStillDecodes() async throws {
        // The published reference documents the `userId` / `createdAt`
        // spelling for membership rows. Both spellings decode, so a server
        // that changes its mind does not blank the roster.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"members":[{"userId":"u1","role":"owner","active":true,
                     "createdAt":"2026-02-22T19:38:07.993Z"}],
         "pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(OrganizationMemberDTO.self, request: Organizations.members(id: "o1"), using: client)

        XCTAssertEqual(page.items.first?.userId, "u1")
        XCTAssertNotNil(page.items.first?.createdAt)
    }

    func test_givenMemberRowWithNeitherIdKey_whenDecoded_thenThrows() async throws {
        // Invalid input: a row with no user key at all is a genuine decode
        // failure, not something to paper over with a placeholder id.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"members":[{"role":"owner","active":true}],
         "pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}
        """#))

        do {
            _ = try await fetchPaginated(OrganizationMemberDTO.self, request: Organizations.members(id: "o1"), using: client)
            XCTFail("Expected a decode failure for a row with no id or userId")
        } catch {
            // Expected.
        }
    }

    func test_givenEmptyMembersPage_whenMembersSent_thenDecodesEmpty() async throws {
        // Boundary: an org page with zero member rows.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"members":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(OrganizationMemberDTO.self, request: Organizations.members(id: "o1"), using: client)

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertFalse(page.pagination.hasMore)
    }

    func test_givenMembershipEnvelope_whenAddMemberSent_thenDecodesNestedMembership() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"message":"added","membership":{"id":"m1","userId":"u2","organizationId":"o1","role":"member","active":true}}
        """#))

        let result = try await client.send(
            Organizations.addMember(id: "o1", AddOrganizationMemberRequest(userId: "u2", role: "member"))
        )

        XCTAssertEqual(result.message, "added")
        XCTAssertEqual(result.membership.id, "m1")
        XCTAssertEqual(result.membership.role, "member")

        let received = await transport.received
        let sent = try XCTUnwrap(received[0].httpBody)
        let decoded = try JSONDecoder().decode(AddOrganizationMemberRequest.self, from: sent)
        XCTAssertEqual(decoded.userId, "u2")
        XCTAssertEqual(decoded.role, "member")
    }

    // MARK: - API failure

    func test_givenBadRequest_whenCreateOrgSent_thenThrowsBadRequest() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"name required"}"#, status: 400))

        do {
            _ = try await client.send(
                Organizations.create(CreateOrganizationRequest(name: "", description: "", isPublic: false))
            )
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "name required"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenEmptyMembersEnvelope_whenMembersSent_thenReturnsNoMembers() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"members":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(OrganizationMemberDTO.self, request: Organizations.members(id: "o1"), using: client)

        XCTAssertTrue(page.items.isEmpty)
    }

    func test_givenNoContent_whenRemoveMemberSent_thenSucceeds() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.empty(status: 204))

        try await client.sendVoid(Organizations.removeMember(id: "o1", userId: "u2"))

        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "DELETE")
        XCTAssertEqual(received[0].url?.path, "/api/organizations/o1/members/u2")
    }

    // MARK: - G25: delete + organization LinkedIn

    func test_givenOrgId_whenDeleteBuilt_thenUsesDeleteVerbAndBearer() {
        // Happy path. Verb confirmed by OPTIONS + the OpenAPI document; never
        // exercised as a live delete (not reversible, shared test account).
        let request = Organizations.delete(id: "o1")
        XCTAssertEqual(request.method, .delete)
        XCTAssertEqual(request.path, "/api/organizations/o1")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertNil(request.body, "Delete carries no body")
    }

    func test_givenOrgLinkedInRoutes_whenBuilt_thenUseTheDeployedVerbs() {
        // The deployed verb set, from OPTIONS and cross-checked against
        // /api/openapi.json. `status` is the only readable one — GET on
        // sync-pages and assignments answers 405 live despite the help page
        // documenting them.
        XCTAssertEqual(Organizations.linkedInStatus(id: "o1").method, .get)
        XCTAssertEqual(Organizations.linkedInStatus(id: "o1").path, "/api/organizations/o1/linkedin/status")

        XCTAssertEqual(Organizations.syncLinkedInPages(id: "o1").method, .post)
        XCTAssertEqual(Organizations.syncLinkedInPages(id: "o1").path, "/api/organizations/o1/linkedin/sync-pages")
        XCTAssertNil(Organizations.syncLinkedInPages(id: "o1").body, "sync-pages takes no body")

        XCTAssertEqual(Organizations.assignLinkedInPage(id: "o1", .init(userId: "u1", pageId: "p1")).method, .put)
        XCTAssertEqual(
            Organizations.assignLinkedInPage(id: "o1", .init(userId: "u1", pageId: "p1")).path,
            "/api/organizations/o1/linkedin/assignments"
        )

        XCTAssertEqual(Organizations.disconnectLinkedIn(id: "o1").method, .delete)
        XCTAssertEqual(
            Organizations.disconnectLinkedIn(id: "o1").path,
            "/api/organizations/o1/linkedin/credential"
        )
    }

    func test_givenAssignment_whenBuilt_thenSendsUserIdAndPageId() async throws {
        // The OpenAPI body schema is a single {userId, pageId} pair — not the
        // "assignment map" the help page describes.
        let (client, transport) = makeClient()
        await transport.enqueue(.json("{}"))

        try await client.sendVoid(
            Organizations.assignLinkedInPage(id: "o1", .init(userId: "u1", pageId: "p1"))
        )

        let received = await transport.received
        let body = try XCTUnwrap(received[0].httpBody)
        let decoded = try JSONDecoder().decode(UpdateOrgLinkedInAssignmentRequest.self, from: body)
        XCTAssertEqual(decoded.userId, "u1")
        XCTAssertEqual(decoded.pageId, "p1")
    }

    func test_givenDisconnectedStatus_whenSent_thenDecodesLiveShape() async throws {
        // The exact body observed live 2026-09-09 on an org with no shared
        // credential, from an account that is a plain member.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"credential":null,"role":"member"}"#))

        let status = try await client.send(Organizations.linkedInStatus(id: "o1"))

        XCTAssertFalse(status.isConnected)
        XCTAssertEqual(status.role, "member")
        XCTAssertNil(status.pages)
    }

    func test_givenDocumentedConnectedStatus_whenSent_thenDecodesConnectedAndPages() async throws {
        // The documented connected shape — never observed live, so the type
        // accepts it alongside the observed one rather than betting on either.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"connected":true,"expiresAt":"2026-12-01T00:00:00.000Z","role":"owner",
         "pages":[{"id":"p1","linkedInPageId":"12345678","pageName":"Acme Corp",
                   "pageLogoUrl":"https://cdn.example/l.png",
                   "lastSyncedAt":"2026-06-12T00:00:00.000Z"}],
         "assignments":[{"userId":"u1","pageId":"p1","pageName":"Acme Corp"}]}
        """#))

        let status = try await client.send(Organizations.linkedInStatus(id: "o1"))

        XCTAssertTrue(status.isConnected)
        XCTAssertEqual(status.role, "owner")
        XCTAssertEqual(status.pages?.first?.pageName, "Acme Corp")
        XCTAssertEqual(status.pages?.first?.linkedInPageId, "12345678")
        XCTAssertEqual(status.assignments?.first?.userId, "u1")
        XCTAssertNotNil(status.expiresAt)
    }

    func test_givenNestedCredential_whenSent_thenInfersConnectedAndExpiry() async throws {
        // Boundary between the two spellings: a nested credential with no
        // `connected` boolean still reads as connected.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"credential":{"expiresAt":"2026-12-01T00:00:00.000Z"},"role":"admin","pages":[]}
        """#))

        let status = try await client.send(Organizations.linkedInStatus(id: "o1"))

        XCTAssertTrue(status.isConnected)
        XCTAssertNotNil(status.credential?.expiresAt)
        XCTAssertEqual(status.pages?.count, 0)
    }

    func test_givenLinkedInFailure_whenStatusSent_thenThrowsForbidden() async throws {
        // Upstream failure surfaces as a typed APIError, not a decode error.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"No access"}"#, status: 403))
        do {
            _ = try await client.send(Organizations.linkedInStatus(id: "o1"))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "No access"))
        }
    }
}
