import XCTest
@testable import InterlinedKit

final class AuthServiceTests: XCTestCase {

    private func makeService(
        tokenStore: TokenStore = InMemoryTokenStore()
    ) -> (AuthService, StubHTTPDataTransport, TokenStore) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(
            baseURL: URL(string: "https://stub.local")!,
            transport: transport,
            authTransport: auth
        )
        return (AuthService(api: client, tokenStore: tokenStore), transport, tokenStore)
    }

    // MARK: - signIn

    func test_givenValidCredentials_whenSignedIn_thenPersistsTokenAndReturnsIt() async throws {
        // Happy path.
        let (service, transport, store) = makeService()
        await transport.enqueue(.json(#"{"token":"il_tok_signin"}"#))

        let token = try await service.signIn(email: "user@example.com", password: "hunter2")

        XCTAssertEqual(token, "il_tok_signin")
        XCTAssertEqual(try store.read(), "il_tok_signin")
        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/auth/sync-token")
        XCTAssertEqual(received[0].httpMethod, "POST")
    }

    func test_givenInvalidCredentials_whenSignedIn_thenThrowsUnauthorized() async throws {
        // Invalid input: bad password → 401 from /sync-token.
        let (service, transport, store) = makeService()
        // The 401 safety-net will try once more via the session transport;
        // enqueue a 401 there too so the test still surfaces the original
        // failure cleanly (the session stub returns its own 401 by default
        // because its queue is empty — but a fail-fast `cannotConnectToHost`
        // is fine since the .none auth requirement skips the safety net).
        await transport.enqueue(.json(#"{"error":"Invalid credentials"}"#, status: 401))

        do {
            _ = try await service.signIn(email: "user@example.com", password: "wrong")
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "Invalid credentials"))
        }
        // Boundary: no token was persisted on failure.
        XCTAssertNil(try store.read())
    }

    func test_givenServerError_whenSignedIn_thenSurfacesError() async throws {
        // API failure class.
        let (service, transport, store) = makeService()
        await transport.enqueue(.json(#"{"error":"oops"}"#, status: 500))

        do {
            _ = try await service.signIn(email: "u@e.com", password: "p")
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "oops"))
        }
        XCTAssertNil(try store.read())
    }

    // MARK: - signOut

    func test_givenStoredToken_whenSignedOut_thenClearsToken() async throws {
        // Happy path: signOut clears persisted state.
        let store = InMemoryTokenStore(initial: "il_tok")
        let (service, _, _) = makeService(tokenStore: store)

        try await service.signOut()

        XCTAssertNil(try store.read())
    }

    func test_givenNoToken_whenSignedOut_thenSucceedsSilently() async throws {
        // Boundary: signOut is idempotent.
        let (service, _, _) = makeService()
        try await service.signOut()
        // No throw is the assertion.
    }

    // MARK: - hasStoredToken

    func test_givenNoToken_whenHasStoredTokenChecked_thenReturnsFalse() async throws {
        // Empty/boundary case.
        let (service, _, _) = makeService()
        let hasToken = try await service.hasStoredToken()
        XCTAssertFalse(hasToken)
    }

    func test_givenStoredToken_whenHasStoredTokenChecked_thenReturnsTrue() async throws {
        // Happy path: app launches with a token.
        let store = InMemoryTokenStore(initial: "il_tok")
        let (service, _, _) = makeService(tokenStore: store)
        let hasToken = try await service.hasStoredToken()
        XCTAssertTrue(hasToken)
    }
}
