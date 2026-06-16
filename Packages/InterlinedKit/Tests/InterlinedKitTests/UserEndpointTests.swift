import XCTest
@testable import InterlinedKit

/// BDD tests for the `User` endpoint builders and their DTOs.
final class UserEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_test"),
        sessionTransport: StubHTTPDataTransport = StubHTTPDataTransport()
    ) -> (APIClient, StubHTTPDataTransport, StubHTTPDataTransport) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: sessionTransport,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport, sessionTransport)
    }

    private func encodedBody(_ request: Request<some Any>) throws -> [String: Any] {
        guard case .json(let value) = request.body else {
            XCTFail("Expected a JSON body"); return [:]
        }
        let data = try JSONCoders.makeEncoder().encode(AnyEncodableUserProbe(value))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // Full user fixture matching the live /api/user envelope.
    private let userEnvelopeJSON = #"""
    {
      "user": {
        "id": "u1", "email": "ada@example.com", "username": "ada",
        "displayName": "Ada", "avatar": null, "bio": "hi", "theme": "dark",
        "emailVerified": true, "pendingEmail": null, "maxMessageLength": 5000,
        "defaultPubliclyVisible": true, "messagesPerPage": 25,
        "viewingPreference": "all", "showPreviews": true,
        "showAdvancedPostSettings": false, "latitude": null, "longitude": null,
        "isPrivateAccount": false, "cleared": false, "githubDefaultRepo": null,
        "openaiApiKey": null, "anthropicApiKey": null,
        "customerStatus": "active", "stripeCustomerId": null,
        "notificationTrayLimit": 50, "createdAt": "2026-01-01T00:00:00.000Z",
        "isAdministrator": false
      }
    }
    """#

    // MARK: - current (GET /api/user)

    func test_givenCurrentUser_whenBuilt_thenGetsUserPathWithBearer() {
        let request = User.current()
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/user")
        XCTAssertEqual(request.auth, .bearer)
    }

    func test_givenUserEnvelope_whenCurrentSent_thenDecodesCustomerStatus() async throws {
        // Happy path: customerStatus is the entitlement-gating field.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(userEnvelopeJSON))

        let response = try await client.send(User.current())
        XCTAssertEqual(response.user.id, "u1")
        XCTAssertEqual(response.user.customerStatus, "active")
        XCTAssertTrue(response.user.emailVerified)
        XCTAssertEqual(response.user.maxMessageLength, 5000)
    }

    func test_givenMinimalUserEnvelope_whenDecoded_thenOptionalsAreNil() throws {
        // Boundary: only required fields present; everything optional decodes nil.
        let json = #"""
        { "user": { "id": "u1", "email": "a@b.c", "username": "ada",
          "emailVerified": false, "customerStatus": "free",
          "createdAt": "2026-01-01T00:00:00Z" } }
        """#
        let response = try JSONCoders.makeDecoder().decode(UserResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.user.customerStatus, "free")
        XCTAssertNil(response.user.displayName)
        XCTAssertNil(response.user.maxMessageLength)
        XCTAssertFalse(response.user.emailVerified)
    }

    func test_givenUnauthorized_whenCurrentSent_thenThrowsUnauthorized() async throws {
        // Upstream API failure. With no token the request still sends; the 401
        // safety net retries through the (empty) session transport, whose
        // failure also surfaces. Both .unauthorized and .transport are valid.
        let (client, transport, _) = makeClient(tokenStore: InMemoryTokenStore())
        await transport.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        do {
            _ = try await client.send(User.current())
            XCTFail("Expected failure")
        } catch let error as APIError {
            switch error {
            case .unauthorized, .transport: break
            default: XCTFail("Expected .unauthorized or .transport, got \(error)")
            }
        }
    }

    // MARK: - identities (session-only)

    func test_givenIdentities_whenBuilt_thenUsesSessionAuth() {
        let request = User.identities()
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/user/identities")
        XCTAssertEqual(request.auth, .session) // decision-0001 allowlist
    }

    func test_givenIdentitiesEnvelope_whenSent_thenDecodesViaSessionTransport() async throws {
        // Happy path: .session routes through the session transport.
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"""
        {"identities":[{"id":"i1","provider":"github","providerUsername":"ada",
          "profileUrl":"https://github.com/ada","avatarUrl":null,
          "connectedAt":"2026-01-01T00:00:00.000Z","lastVerifiedAt":null}]}
        """#))
        let (client, _, _) = makeClient(sessionTransport: session)

        let response = try await client.send(User.identities())
        XCTAssertEqual(response.identities.count, 1)
        XCTAssertEqual(response.identities.first?.provider, "github")
        XCTAssertNil(response.identities.first?.lastVerifiedAt)
    }

    func test_givenNoIdentities_whenSent_thenDecodesEmpty() async throws {
        // Boundary: account with no linked identities.
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"{"identities":[]}"#))
        let (client, _, _) = makeClient(sessionTransport: session)

        let response = try await client.send(User.identities())
        XCTAssertTrue(response.identities.isEmpty)
    }

    // MARK: - organizations (session-only)

    func test_givenOrganizations_whenBuilt_thenUsesSessionAuth() {
        let request = User.organizations()
        XCTAssertEqual(request.path, "/api/user/organizations")
        XCTAssertEqual(request.auth, .session)
    }

    func test_givenOrganizationsEnvelope_whenSent_thenDecodesRoleAndMetadata() async throws {
        // Happy path through the session transport.
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"""
        {"organizations":[{"id":"o1","name":"Acme","slug":"acme","description":"x",
          "avatar":null,"isPublic":true,"isSystem":false,
          "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z",
          "deletedAt":null,"role":"admin","joinedAt":"2026-02-01T00:00:00.000Z"}]}
        """#))
        let (client, _, _) = makeClient(sessionTransport: session)

        let response = try await client.send(User.organizations())
        XCTAssertEqual(response.organizations.first?.role, "admin")
        XCTAssertEqual(response.organizations.first?.name, "Acme")
    }

    func test_givenOrganizationsFailure_whenSent_thenThrowsForbidden() async throws {
        // Upstream API failure on the session transport.
        let session = StubHTTPDataTransport()
        await session.enqueue(.json(#"{"error":"No access"}"#, status: 403))
        let (client, _, _) = makeClient(sessionTransport: session)
        do {
            _ = try await client.send(User.organizations())
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "No access"))
        }
    }

    // MARK: - update

    func test_givenProfilePatch_whenUpdateBuilt_thenPostsOnlySetFields() throws {
        // Happy path + boundary: nil fields omitted.
        let request = User.update(UpdateUserRequest(displayName: "New Name", bio: nil))
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/user/update")
        XCTAssertEqual(request.auth, .bearer)
        let body = try encodedBody(request)
        XCTAssertEqual(body["displayName"] as? String, "New Name")
        XCTAssertNil(body["bio"])
        XCTAssertNil(body["theme"])
    }

    func test_givenEmptyPatch_whenUpdateBuilt_thenEncodesEmptyObject() throws {
        // Boundary: no fields set → empty JSON object, not a crash.
        let request = User.update(UpdateUserRequest())
        let body = try encodedBody(request)
        XCTAssertTrue(body.isEmpty)
    }

    func test_givenValidPatch_whenUpdateSent_thenReturnsUpdatedUser() async throws {
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(userEnvelopeJSON))
        let response = try await client.send(User.update(UpdateUserRequest(displayName: "Ada")))
        XCTAssertEqual(response.user.username, "ada")
        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "POST")
    }

    func test_givenInvalidPatch_whenUpdateSent_thenThrowsBadRequest() async throws {
        // Upstream API failure.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"error":"Invalid theme"}"#, status: 400))
        do {
            _ = try await client.send(User.update(UpdateUserRequest(theme: "neon")))
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "Invalid theme"))
        }
    }

    // MARK: - avatar

    func test_givenAvatarBytes_whenUploadAvatarBuilt_thenUsesRawBody() {
        let request = User.uploadAvatar(Data([0x89]), contentType: "image/jpeg")
        XCTAssertEqual(request.path, "/api/user/avatar/upload")
        XCTAssertEqual(request.auth, .bearer)
        guard case .raw(_, let contentType) = request.body else {
            return XCTFail("Expected raw body")
        }
        XCTAssertEqual(contentType, "image/jpeg")
    }

    func test_givenURL_whenAvatarFromURLBuilt_thenPostsURLJSON() throws {
        let request = User.avatarFromURL("https://img/x.png")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/user/avatar/from-url")
        XCTAssertEqual(try encodedBody(request)["url"] as? String, "https://img/x.png")
    }

    func test_givenValidAvatarURL_whenSent_thenDecodesHostedURL() async throws {
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"url":"https://cdn/avatar.png"}"#))
        let response = try await client.send(User.avatarFromURL("https://img/x.png"))
        XCTAssertEqual(response.url, "https://cdn/avatar.png")
    }

    // MARK: - change email

    func test_givenNewEmail_whenChangeEmailBuilt_thenPostsNewEmail() throws {
        let request = User.requestEmailChange(ChangeEmailRequest(newEmail: "new@e.com", password: "p"))
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/user/change-email/request")
        XCTAssertEqual(request.auth, .bearer)
        let body = try encodedBody(request)
        XCTAssertEqual(body["newEmail"] as? String, "new@e.com")
        XCTAssertEqual(body["password"] as? String, "p")
    }

    func test_givenNoPassword_whenChangeEmailBuilt_thenOmitsPassword() throws {
        // Boundary: password optional (OAuth-only accounts).
        let request = User.requestEmailChange(ChangeEmailRequest(newEmail: "new@e.com"))
        let body = try encodedBody(request)
        XCTAssertEqual(body["newEmail"] as? String, "new@e.com")
        XCTAssertNil(body["password"])
    }

    func test_givenChangeEmailConflict_whenSent_thenThrowsBadRequest() async throws {
        // Upstream API failure: email taken.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"error":"Email already in use"}"#, status: 400))
        do {
            _ = try await client.send(User.requestEmailChange(ChangeEmailRequest(newEmail: "taken@e.com")))
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "Email already in use"))
        }
    }

    // MARK: - delete

    func test_givenDelete_whenBuilt_thenPostsDeletePath() {
        let request = User.delete()
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/user/delete")
        XCTAssertEqual(request.auth, .bearer)
    }

    func test_givenValidDelete_whenSent_thenDecodesMessage() async throws {
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"message":"Account deleted"}"#))
        let response = try await client.send(User.delete(DeleteAccountRequest(password: "p")))
        XCTAssertEqual(response.message, "Account deleted")
    }

    func test_givenDeleteRejected_whenSent_thenThrowsForbidden() async throws {
        // Upstream API failure: wrong password.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"error":"Incorrect password"}"#, status: 403))
        do {
            _ = try await client.send(User.delete(DeleteAccountRequest(password: "wrong")))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "Incorrect password"))
        }
    }
}

private struct AnyEncodableUserProbe: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { self._encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
