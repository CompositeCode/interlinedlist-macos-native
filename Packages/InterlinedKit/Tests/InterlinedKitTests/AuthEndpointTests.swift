import XCTest
@testable import InterlinedKit

/// BDD tests for the `Auth` endpoint builders and the additive `AuthService`
/// methods (forgot/reset password, verification email, verify email, logout).
final class AuthEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeService(
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_test"),
        sessionTransport: StubHTTPDataTransport = StubHTTPDataTransport()
    ) -> (AuthService, StubHTTPDataTransport, StubHTTPDataTransport) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: sessionTransport,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (AuthService(api: client, tokenStore: tokenStore), transport, sessionTransport)
    }

    private func encodedBody(_ request: Request<some Any>) throws -> [String: Any] {
        guard case .json(let value) = request.body else {
            XCTFail("Expected a JSON body"); return [:]
        }
        let data = try JSONCoders.makeEncoder().encode(AnyEncodableAuthProbe(value))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Builder shape

    func test_givenEmail_whenForgotPasswordBuilt_thenTargetsWorkingPathNoAuth() throws {
        // The corrected, live path — NOT /api/auth/password-reset/request.
        let request = Auth.forgotPassword(email: "ada@e.com")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/auth/forgot-password")
        XCTAssertEqual(request.auth, .none)
        XCTAssertEqual(try encodedBody(request)["email"] as? String, "ada@e.com")
    }

    func test_givenTokenAndPassword_whenResetPasswordBuilt_thenPostsBothFields() throws {
        let request = Auth.resetPassword(token: "rt", newPassword: "newpass")
        XCTAssertEqual(request.path, "/api/auth/reset-password")
        XCTAssertEqual(request.auth, .none)
        let body = try encodedBody(request)
        XCTAssertEqual(body["token"] as? String, "rt")
        XCTAssertEqual(body["password"] as? String, "newpass")
    }

    func test_givenEmail_whenSendVerificationBuilt_thenUsesBearerAuth() throws {
        // Live endpoint requires an authenticated caller (401 anonymous).
        let request = Auth.sendVerificationEmail(email: "ada@e.com")
        XCTAssertEqual(request.path, "/api/auth/send-verification-email")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertEqual(try encodedBody(request)["email"] as? String, "ada@e.com")
    }

    func test_givenToken_whenVerifyEmailBuilt_thenPostsTokenNoAuth() throws {
        let request = Auth.verifyEmail(token: "vt")
        XCTAssertEqual(request.path, "/api/auth/verify-email")
        XCTAssertEqual(request.auth, .none)
        XCTAssertEqual(try encodedBody(request)["token"] as? String, "vt")
    }

    func test_givenLogout_whenBuilt_thenUsesSessionAuthWithNoBody() {
        let request = Auth.logout()
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/auth/logout")
        XCTAssertEqual(request.auth, .session) // session-only per coverage matrix
        XCTAssertNil(request.body)
    }

    // MARK: - requestPasswordReset (corrected path)

    func test_givenEmail_whenRequestPasswordReset_thenHitsForgotPasswordPath() async throws {
        // Happy path: routes to the working /api/auth/forgot-password.
        let (service, transport, _) = makeService()
        await transport.enqueue(.json(#"{"message":"If that email exists, a reset link has been sent."}"#))

        try await service.requestPasswordReset(email: "ada@e.com")

        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/auth/forgot-password")
        XCTAssertEqual(received[0].httpMethod, "POST")
    }

    func test_givenServerError_whenRequestPasswordReset_thenSurfacesError() async throws {
        // Upstream API failure.
        let (service, transport, _) = makeService()
        await transport.enqueue(.json(#"{"error":"boom"}"#, status: 500))
        do {
            try await service.requestPasswordReset(email: "ada@e.com")
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - resetPassword

    func test_givenTokenAndNewPassword_whenResetPassword_thenSucceeds() async throws {
        // Happy path.
        let (service, transport, _) = makeService()
        await transport.enqueue(.json(#"{"message":"Password reset successfully"}"#))
        try await service.resetPassword(token: "rt", newPassword: "newpass")
        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/auth/reset-password")
    }

    func test_givenExpiredToken_whenResetPassword_thenThrowsBadRequest() async throws {
        // Invalid input / upstream failure: stale or bad reset token.
        let (service, transport, _) = makeService()
        await transport.enqueue(.json(#"{"error":"Invalid or expired token"}"#, status: 400))
        do {
            try await service.resetPassword(token: "stale", newPassword: "p")
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "Invalid or expired token"))
        }
    }

    // MARK: - sendVerificationEmail

    func test_givenEmail_whenSendVerificationEmail_thenSucceeds() async throws {
        // Happy path (bearer caller).
        let (service, transport, _) = makeService()
        await transport.enqueue(.json(#"{"message":"sent"}"#))
        try await service.sendVerificationEmail(email: "ada@e.com")
        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/auth/send-verification-email")
        XCTAssertEqual(received[0].value(forHTTPHeaderField: "Authorization"), "Bearer il_tok_test")
    }

    func test_givenUnauthenticated_whenSendVerificationEmail_thenSurfacesUnauthorized() async throws {
        // Upstream API failure: anonymous caller is rejected. Provide matching
        // 401 on both transports so the safety net's session retry also fails
        // cleanly with an unauthorized.
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        let (service, transport, _) = makeService(
            tokenStore: InMemoryTokenStore(),
            sessionTransport: session
        )
        await transport.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        do {
            try await service.sendVerificationEmail(email: "ada@e.com")
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "Unauthorized"))
        }
    }

    // MARK: - verifyEmail

    func test_givenValidToken_whenVerifyEmail_thenSucceeds() async throws {
        // Happy path.
        let (service, transport, _) = makeService()
        await transport.enqueue(.json(#"{"message":"Email verified successfully"}"#))
        try await service.verifyEmail(token: "vt")
        let received = await transport.received
        XCTAssertEqual(received[0].url?.path, "/api/auth/verify-email")
    }

    func test_givenInvalidToken_whenVerifyEmail_thenThrowsBadRequest() async throws {
        // Invalid input: bad verification token.
        let (service, transport, _) = makeService()
        await transport.enqueue(.json(#"{"error":"Invalid token"}"#, status: 400))
        do {
            try await service.verifyEmail(token: "bad")
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "Invalid token"))
        }
    }

    // MARK: - logout (session)

    func test_givenLogout_whenCalled_thenSendsViaSessionTransport() async throws {
        // Happy path: .session routes through the session transport.
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"{"message":"Logged out successfully"}"#))
        let (service, bearer, _) = makeService(sessionTransport: session)

        try await service.logout()

        // The bearer transport must not have been used for a session request.
        let bearerReceived = await bearer.received
        XCTAssertTrue(bearerReceived.isEmpty)
        let sessionReceived = await session.received
        XCTAssertEqual(sessionReceived.count, 1)
        XCTAssertEqual(sessionReceived[0].url?.path, "/api/auth/logout")
    }

    func test_givenLogoutFailure_whenCalled_thenSurfacesError() async throws {
        // Upstream API failure on the session transport.
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"{"error":"No session"}"#, status: 401))
        let (service, _, _) = makeService(sessionTransport: session)
        do {
            try await service.logout()
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "No session"))
        }
    }

    func test_givenLogout_whenCalled_thenDoesNotClearBearerToken() async throws {
        // Boundary: server-side logout is distinct from local signOut; the
        // bearer token in the store is untouched.
        let store = InMemoryTokenStore(initial: "il_tok_keep")
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"{"message":"Logged out successfully"}"#))
        let (service, _, _) = makeService(tokenStore: store, sessionTransport: session)

        try await service.logout()

        XCTAssertEqual(try store.read(), "il_tok_keep")
    }

    // MARK: - blueskyStatus (GET /api/auth/bluesky/status) — NW-4

    func test_givenNoParams_whenBlueskyStatusBuilt_thenTargetsBlueskyStatusPath() throws {
        let request = Auth.blueskyStatus()
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/auth/bluesky/status")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertTrue(request.query.isEmpty)
    }

    // MARK: - mastodonStatus (GET /api/auth/mastodon/status) — NW-4

    func test_givenInstance_whenMastodonStatusBuilt_thenIncludesInstanceQuery() throws {
        let request = Auth.mastodonStatus(instance: "mastodon.social")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/auth/mastodon/status")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertTrue(request.query.contains { $0.name == "instance" && $0.value == "mastodon.social" })
    }

    func test_givenEmptyInstance_whenMastodonStatusBuilt_thenInstanceQueryPresent() throws {
        let request = Auth.mastodonStatus(instance: "")
        XCTAssertTrue(request.query.contains { $0.name == "instance" && $0.value == "" })
    }

    // MARK: - ProviderStatusResponse decode (NW-4)

    func test_givenConfiguredTrue_whenProviderStatusDecoded_thenConfiguredIsTrue() throws {
        // Happy path: the server reports the provider is configured.
        let json = #"{"configured":true}"#
        let decoded = try JSONCoders.makeDecoder().decode(ProviderStatusResponse.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.configured)
    }

    func test_givenConfiguredFalse_whenProviderStatusDecoded_thenConfiguredIsFalse() throws {
        // Boundary: a deployment that has not configured the provider.
        let json = #"{"configured":false}"#
        let decoded = try JSONCoders.makeDecoder().decode(ProviderStatusResponse.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.configured)
    }

    func test_givenMissingConfiguredField_whenProviderStatusDecoded_thenThrows() throws {
        // Invalid input: a malformed or partial response must fail rather
        // than silently defaulting (mirrors the LinkedInStatusResponse test).
        let json = #"{"other":"value"}"#
        XCTAssertThrowsError(
            try JSONCoders.makeDecoder().decode(ProviderStatusResponse.self, from: Data(json.utf8))
        )
    }

    // MARK: - linkIdentity (POST /api/auth/{provider}/link) — NW-5

    func test_givenGitHubCodeAndState_whenLinkIdentityBuilt_thenPostsToGitHubLinkPath() throws {
        let request = Auth.linkIdentity(provider: .github, code: "code123", state: "state456")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/auth/github/link")
        XCTAssertEqual(request.auth, .bearer)
        let body = try encodedBody(request)
        XCTAssertEqual(body["code"] as? String, "code123")
        XCTAssertEqual(body["state"] as? String, "state456")
    }

    func test_givenBlueskyProvider_whenLinkIdentityBuilt_thenPathUsesBluesky() throws {
        let request = Auth.linkIdentity(provider: .bluesky, code: "c", state: "s")
        XCTAssertEqual(request.path, "/api/auth/bluesky/link")
    }
}

private struct AnyEncodableAuthProbe: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { self._encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
