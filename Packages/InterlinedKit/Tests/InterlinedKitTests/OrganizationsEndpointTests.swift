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
        XCTAssertEqual(Organizations.update(id: "o1", UpdateOrganizationRequest(name: "x")).method, .patch)

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

    func test_givenMembersEnvelope_whenMembersSent_thenDecodesMembershipRows() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"members":[{"userId":"u1","role":"owner","active":true},{"userId":"u2","role":"member"}],
         "pagination":{"total":2,"limit":50,"offset":0,"hasMore":false}}
        """#))

        let page = try await fetchPaginated(OrganizationMemberDTO.self, request: Organizations.members(id: "o1"), using: client)

        XCTAssertEqual(page.items.map(\.role), ["owner", "member"])
        XCTAssertEqual(page.items.first?.active, true)
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
}
