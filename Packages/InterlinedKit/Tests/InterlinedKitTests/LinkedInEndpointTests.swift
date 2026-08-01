import XCTest
@testable import InterlinedKit

/// BDD tests for the LinkedIn posting-targets endpoint group (the-gaps.md G11a).
final class LinkedInEndpointTests: XCTestCase {

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

    func test_givenLinkedInBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(LinkedIn.postingTargets().path, "/api/linkedin/posting-targets")
        XCTAssertEqual(LinkedIn.postingTargets().method, .get)
        XCTAssertEqual(LinkedIn.postingTargets().auth, .bearer)
        XCTAssertEqual(LinkedIn.targets().path, "/api/linkedin/targets")
    }

    func test_givenPostingTargetsBody_whenSent_thenDecodesTargetsAndOrgScopeFlag() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"targets":[{"kind":"personal","label":"Adron Hall","avatarUrl":"https://cdn/a.png","enabled":true}],
         "orgScopeMissing":true}
        """#))

        let response = try await client.send(LinkedIn.postingTargets())

        XCTAssertEqual(response.targets.map(\.kind), ["personal"])
        XCTAssertEqual(response.targets.first?.enabled, true)
        XCTAssertEqual(response.orgScopeMissing, true)
    }

    func test_givenServerError_whenSent_thenThrowsHttpStatus() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"boom"}"#, status: 500))

        do {
            _ = try await client.send(LinkedIn.postingTargets())
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenNoTargets_whenSent_thenReturnsEmpty() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"targets":[]}"#))

        let response = try await client.send(LinkedIn.targets())

        XCTAssertTrue(response.targets.isEmpty)
    }
}
