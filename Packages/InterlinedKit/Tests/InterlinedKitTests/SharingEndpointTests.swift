import XCTest
@testable import InterlinedKit

/// BDD tests for the Sharing (share-links) endpoint group (work-consolidation.md G3).
/// Fixtures mirror shapes captured live 2026-07-31.
final class SharingEndpointTests: XCTestCase {

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

    func test_givenSharingBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Sharing.listShareLinks(listId: "l1").path, "/api/lists/l1/share-links")
        XCTAssertEqual(Sharing.listShareLinks(listId: "l1").method, .get)
        XCTAssertEqual(Sharing.createListShareLink(listId: "l1", CreateShareLinkRequest(role: "watcher")).method, .post)
        XCTAssertEqual(Sharing.revokeListShareLink(listId: "l1", token: "t9").method, .delete)
        XCTAssertEqual(Sharing.revokeListShareLink(listId: "l1", token: "t9").path, "/api/lists/l1/share-links/t9")
        XCTAssertEqual(Sharing.resolveListShare(token: "t9").path, "/api/lists/shared/t9")
        XCTAssertEqual(Sharing.claimListShare(token: "t9").method, .post)

        XCTAssertEqual(Sharing.documentShareLinks(documentId: "d1").path, "/api/documents/d1/share-links")
        XCTAssertEqual(Sharing.resolveDocumentShare(token: "t9").path, "/api/documents/shared/t9")
        XCTAssertEqual(Sharing.createDocumentShareLink(documentId: "d1", CreateShareLinkRequest(role: "manager")).path, "/api/documents/d1/share-links")
    }

    // MARK: - Happy path

    func test_givenCreateBody_whenCreatingListLink_thenDecodesLinkAndEncodesRole() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"token":"tok9","url":"https://x/lists/shared/tok9","role":"watcher","expiresAt":null}"#))

        let link = try await client.send(Sharing.createListShareLink(listId: "l1", CreateShareLinkRequest(role: "watcher")))

        XCTAssertEqual(link.token, "tok9")
        XCTAssertEqual(link.role, "watcher")
        let received = await transport.received
        let body = try XCTUnwrap(received[0].httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["role"] as? String, "watcher")
    }

    func test_givenLinksBody_whenListing_thenDecodesRows() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"shareLinks":[{"token":"tok9","role":"collaborator","expiresAt":null,
          "createdAt":"2026-07-31T23:07:24.019Z","revokedAt":null,"url":"https://x/s/tok9"}]}
        """#))

        let response = try await client.send(Sharing.listShareLinks(listId: "l1"))

        XCTAssertEqual(response.shareLinks.map(\.token), ["tok9"])
        XCTAssertEqual(response.shareLinks.first?.role, "collaborator")
    }

    func test_givenResolveBody_whenResolvingListShare_thenDecodesRoleAndList() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"role":"watcher","canClaim":false,"needsAuth":false,
         "list":{"id":"l1","title":"Bikes","description":null,"isPublic":false,"updatedAt":"2026-07-18T19:14:35.099Z"}}
        """#))

        let resolved = try await client.send(Sharing.resolveListShare(token: "tok9"))

        XCTAssertEqual(resolved.role, "watcher")
        XCTAssertEqual(resolved.list?.title, "Bikes")
    }

    func test_givenRevokeBody_whenRevoking_thenDecodesRevoked() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"revoked":true}"#))

        let response = try await client.send(Sharing.revokeListShareLink(listId: "l1", token: "tok9"))

        XCTAssertEqual(response.revoked, true)
    }

    // MARK: - API failure

    func test_givenForbidden_whenCreatingLink_thenThrowsForbidden() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"subscriber required"}"#, status: 403))

        do {
            _ = try await client.send(Sharing.createListShareLink(listId: "l1", CreateShareLinkRequest(role: "watcher")))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "subscriber required"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoLinks_whenListing_thenReturnsEmpty() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"shareLinks":[]}"#))

        let response = try await client.send(Sharing.documentShareLinks(documentId: "d1"))

        XCTAssertTrue(response.shareLinks.isEmpty)
    }
}
