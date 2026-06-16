import XCTest
@testable import InterlinedKit

/// A controllable `SessionEstablisher` that records how many times login
/// was triggered, so tests can assert laziness (login only on the first
/// `.session` request) and the 401 safety net.
private actor CountingSessionEstablisher: SessionEstablisher {
    private(set) var count: Int = 0
    var shouldThrow: (any Error)?

    func setShouldThrow(_ error: (any Error)?) {
        self.shouldThrow = error
    }

    func establishIfNeeded() async throws {
        if let err = shouldThrow { throw err }
        count += 1
    }
}

final class AuthTransportTests: XCTestCase {

    private let testURL = URL(string: "https://stub.local/api/test")!

    private func makeRequest(url: URL? = nil) -> URLRequest {
        URLRequest(url: url ?? testURL)
    }

    // MARK: - Happy path: bearer routing

    func test_givenBearerRequirement_whenExecuted_thenAttachesAuthorizationAndUsesBaseTransport() async throws {
        // Given
        let tokenStore = InMemoryTokenStore(initial: "il_tok_abc")
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        await base.enqueue(.json("{}"))

        let transport = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: session,
            sessionEstablisher: NullSessionEstablisher()
        )

        // When
        _ = try await transport.execute(makeRequest(), auth: .bearer, base: base)

        // Then — went through base, session untouched.
        let baseReceived = await base.received
        let sessionReceived = await session.received
        XCTAssertEqual(baseReceived.count, 1)
        XCTAssertEqual(sessionReceived.count, 0)
        XCTAssertEqual(
            baseReceived[0].value(forHTTPHeaderField: "Authorization"),
            "Bearer il_tok_abc"
        )
    }

    // MARK: - Session routing

    func test_givenSessionRequirement_whenExecuted_thenEstablishesAndRoutesViaSessionTransport() async throws {
        // Given
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        await session.enqueue(.json("{}"))
        let establisher = CountingSessionEstablisher()

        let transport = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(),
            sessionTransport: session,
            sessionEstablisher: establisher
        )

        // When
        _ = try await transport.execute(makeRequest(), auth: .session, base: base)

        // Then
        let count = await establisher.count
        let sessionReceived = await session.received
        let baseReceived = await base.received
        XCTAssertEqual(count, 1)
        XCTAssertEqual(sessionReceived.count, 1)
        XCTAssertEqual(baseReceived.count, 0)
    }

    func test_givenMultipleSessionRequests_whenExecuted_thenEstablishesOnce() async throws {
        // Given — laziness: subsequent session calls reuse the cookie.
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        await session.enqueue(.json("{}"))
        await session.enqueue(.json("{}"))
        await session.enqueue(.json("{}"))
        let establisher = CountingSessionEstablisher()

        let transport = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(),
            sessionTransport: session,
            sessionEstablisher: establisher
        )

        // When
        for _ in 0..<3 {
            _ = try await transport.execute(makeRequest(), auth: .session, base: base)
        }

        // Then
        let count = await establisher.count
        let sessionReceived = await session.received
        XCTAssertEqual(count, 1)
        XCTAssertEqual(sessionReceived.count, 3)
    }

    // MARK: - No auth

    func test_givenNoneRequirement_whenExecuted_thenSendsThroughBaseWithoutAuthorization() async throws {
        // Given — boundary: unauthenticated endpoints (login, register).
        let tokenStore = InMemoryTokenStore(initial: "il_tok_abc")
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        await base.enqueue(.json("{}"))

        let transport = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: session,
            sessionEstablisher: NullSessionEstablisher()
        )

        // When
        _ = try await transport.execute(makeRequest(), auth: .none, base: base)

        // Then — no authorization header even though a token exists.
        let received = await base.received
        XCTAssertNil(received[0].value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - 401 retry safety net (decision 0001)

    func test_givenBearerRequest401_whenSentThroughClient_thenRetriesViaSessionTransportOnce() async throws {
        // Given — the safety net: an unexpected 401 on a Bearer request is
        // re-tried once through the session transport. This catches future
        // API drift where an endpoint silently flips Bearer→Session-only.
        let tokenStore = InMemoryTokenStore(initial: "il_tok_xyz")
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        // First Bearer attempt: 401.
        await base.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        // Session retry: 200.
        await session.enqueue(.json(#"{"hello":"recovered"}"#))

        let authTransport = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: session,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(
            baseURL: URL(string: "https://stub.local")!,
            transport: base,
            authTransport: authTransport,
            retryPolicy: .none
        )

        struct R: Decodable, Sendable, Equatable { let hello: String }
        let result = try await client.send(
            Request<R>(method: .get, path: "/api/replies", auth: .bearer)
        )

        // Then
        let baseReceived = await base.received
        let sessionReceived = await session.received
        XCTAssertEqual(result, R(hello: "recovered"))
        XCTAssertEqual(baseReceived.count, 1)
        XCTAssertEqual(sessionReceived.count, 1)
    }

    func test_givenBearer401AndSession401_whenSent_thenSurfacesUnauthorized() async throws {
        // Given — invalid input class: credentials genuinely bad. Both
        // attempts return 401; the second 401 must propagate.
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        await base.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        await session.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))

        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok"),
            sessionTransport: session,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(
            baseURL: URL(string: "https://stub.local")!,
            transport: base,
            authTransport: auth
        )

        struct R: Decodable, Sendable { let x: String }
        do {
            _ = try await client.send(Request<R>(method: .get, path: "/api/x"))
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        }
    }
}
