import XCTest
@testable import InterlinedKit

/// BDD tests for the Sessions endpoint (work-consolidation.md G19).
final class SessionsEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient() -> (APIClient, StubHTTPDataTransport) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_abc"),
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        return (APIClient(baseURL: baseURL, transport: transport, authTransport: auth), transport)
    }

    // MARK: - Builder shape

    func test_givenSessionBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        let list = Sessions.list()
        XCTAssertEqual(list.method, .get)
        XCTAssertEqual(list.path, "/api/user/sessions")
        XCTAssertEqual(list.auth, .bearer)

        let revoke = Sessions.revoke(id: "sess_9")
        XCTAssertEqual(revoke.method, .delete)
        XCTAssertEqual(revoke.path, "/api/user/sessions/sess_9")
        XCTAssertEqual(revoke.auth, .bearer)
    }

    // MARK: - Happy path

    func test_givenSessionsBody_whenSent_thenDecodesEveryField() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "sessions": [
            { "id": "sess_1", "deviceLabel": "MacBook Pro",
              "createdAt": "2026-09-01T10:00:00Z",
              "lastUsedAt": "2026-09-05T18:22:00Z", "isCurrent": true },
            { "id": "sess_2", "deviceLabel": "iPhone", "isCurrent": false }
        ] }
        """#))

        let response = try await client.send(Sessions.list())

        XCTAssertEqual(response.sessions.count, 2)
        XCTAssertEqual(response.sessions[0].id, "sess_1")
        XCTAssertEqual(response.sessions[0].deviceLabel, "MacBook Pro")
        XCTAssertEqual(response.sessions[0].isCurrent, true)
        XCTAssertEqual(response.sessions[1].id, "sess_2")
        XCTAssertNil(response.sessions[1].createdAt)
    }

    // MARK: - Invalid / tolerant input

    func test_givenBareArray_whenSent_thenStillDecodes() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"[ { "id": "sess_3" } ]"#))

        let response = try await client.send(Sessions.list())

        XCTAssertEqual(response.sessions.map(\.id), ["sess_3"])
        XCTAssertNil(response.sessions[0].deviceLabel)
    }

    // MARK: - API failure

    func test_givenServerError_whenListSent_thenThrowsHttpStatus() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"boom"}"#, status: 500))

        do {
            _ = try await client.send(Sessions.list())
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            guard case .httpStatus(let code, _) = error else {
                return XCTFail("Expected .httpStatus, got \(error)")
            }
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoSessions_whenSent_thenReturnsEmptyList() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "sessions": [] }"#))

        let response = try await client.send(Sessions.list())

        XCTAssertTrue(response.sessions.isEmpty)
    }
}
