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

    // MARK: - accountStatus (GitHub #42)

    /// Happy path: the field the client previously dropped on the floor.
    /// Verified against the live payload 2026-09-09 (`"accountStatus":"active"`).
    func test_givenUserEnvelopeWithAccountStatus_whenDecoded_thenCarriesRawStatus() throws {
        let json = #"""
        { "user": { "id": "u1", "email": "a@b.c", "username": "ada",
          "emailVerified": true, "customerStatus": "subscriber",
          "accountStatus": "active",
          "createdAt": "2026-01-01T00:00:00Z" } }
        """#

        let response = try JSONCoders.makeDecoder().decode(UserResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.user.accountStatus, "active")
    }

    /// Boundary: the field is absent, as it is on any older server. It must
    /// decode to nil rather than failing — the domain layer supplies the
    /// fail-open default.
    func test_givenUserEnvelopeWithoutAccountStatus_whenDecoded_thenNilNotAThrow() throws {
        let json = #"""
        { "user": { "id": "u1", "email": "a@b.c", "username": "ada",
          "emailVerified": false, "customerStatus": "free",
          "createdAt": "2026-01-01T00:00:00Z" } }
        """#

        let response = try JSONCoders.makeDecoder().decode(UserResponse.self, from: Data(json.utf8))

        XCTAssertNil(response.user.accountStatus)
    }

    /// Upstream drift: the OpenAPI schema declares `accountStatus` as a bare
    /// string with no enum, so the server may send a value this client has
    /// never seen. Decoding it loosely means one unknown status can never fail
    /// the whole account decode and sign the user out.
    func test_givenUnrecognisedAccountStatus_whenDecoded_thenPreservedNotRejected() throws {
        let json = #"""
        { "user": { "id": "u1", "email": "a@b.c", "username": "ada",
          "emailVerified": true, "customerStatus": "free",
          "accountStatus": "shadow-realm",
          "createdAt": "2026-01-01T00:00:00Z" } }
        """#

        let response = try JSONCoders.makeDecoder().decode(UserResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.user.accountStatus, "shadow-realm")
    }

    /// Invalid input: a null literal is distinct from an absent key on the
    /// wire, and must land on the same nil rather than throwing.
    func test_givenNullAccountStatus_whenDecoded_thenNil() throws {
        let json = #"""
        { "user": { "id": "u1", "email": "a@b.c", "username": "ada",
          "emailVerified": true, "customerStatus": "free",
          "accountStatus": null,
          "createdAt": "2026-01-01T00:00:00Z" } }
        """#

        let response = try JSONCoders.makeDecoder().decode(UserResponse.self, from: Data(json.utf8))

        XCTAssertNil(response.user.accountStatus)
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

    // MARK: - identities (Bearer — corrected 2026-09-15, GitHub #47)

    func test_givenIdentities_whenBuilt_thenUsesBearerAuth() {
        // CORRECTED: this route was on the decision-0001 session allowlist. A
        // live probe with a valid Bearer sync-token returns 200 with the full
        // identity list, so the annotation was wrong — the same class of error
        // as the `send-verification-email` correction in PR #83, in the opposite
        // direction. It was not a hard failure (the kit has a cookie-session
        // transport that lazily logs in) but it cost an extra credentialed
        // round-trip on every load of the Identities pane.
        let request = User.identities()
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/user/identities")
        XCTAssertEqual(request.auth, .bearer)
    }

    func test_givenIdentitiesEnvelope_whenSent_thenDecodesTheCapturedShape() async throws {
        // The payload is the one captured live on 2026-09-15, including the
        // instance-qualified Mastodon provider token that used to decode as an
        // unknown provider.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"""
        {"identities":[
          {"id":"i1","provider":"github","providerUsername":"ada",
           "profileUrl":"https://github.com/ada","avatarUrl":null,
           "connectedAt":"2026-01-01T00:00:00.000Z","lastVerifiedAt":null},
          {"id":"i2","provider":"mastodon:techhub.social",
           "providerUsername":"crew@techhub.social",
           "profileUrl":"https://techhub.social/@crew","avatarUrl":null,
           "connectedAt":"2026-04-07T16:35:32.476Z",
           "lastVerifiedAt":"2026-08-22T06:00:41.130Z"}]}
        """#))

        let response = try await client.send(User.identities())
        XCTAssertEqual(response.identities.count, 2)
        XCTAssertEqual(response.identities.first?.provider, "github")
        XCTAssertEqual(
            response.identities.last?.provider,
            "mastodon:techhub.social",
            "the kit passes the qualified token through; the domain splits it"
        )
    }

    func test_givenNoIdentities_whenSent_thenDecodesEmpty() async throws {
        // Boundary: account with no linked identities.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"identities":[]}"#))

        let response = try await client.send(User.identities())
        XCTAssertTrue(response.identities.isEmpty)
    }

    // MARK: - unlink / verify (GitHub #47)

    func test_givenAnUnlink_whenBuilt_thenTheProviderTravelsAsAQueryParameter() {
        let request = User.unlinkIdentity(provider: "mastodon:techhub.social")
        XCTAssertEqual(request.method, .delete)
        XCTAssertEqual(request.path, "/api/user/identities")
        XCTAssertEqual(request.auth, .bearer)
        // Instance-qualified: a bare "mastodon" on an account with two instances
        // is ambiguous enough that the server could disconnect the wrong one.
        XCTAssertEqual(
            request.query.first(where: { $0.name == "provider" })?.value,
            "mastodon:techhub.social"
        )
    }

    func test_givenAVerify_whenBuilt_thenTheProviderIsInTheBody() throws {
        let request = User.verifyIdentity(provider: "bluesky")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/user/identities/verify")
        XCTAssertEqual(try encodedBody(request)["provider"] as? String, "bluesky")
    }

    func test_givenAVerifyResponseWithNoVerifiedKey_whenDecoding_thenItCountsAsVerified() throws {
        // The verify write was not exercised live — it mutates a shared recon
        // account's connection state — so the decoder is permissive and a 2xx
        // with an unexpected body is read as success. The route answering at all
        // is the signal; claiming "not responding" on a shape we have not seen
        // would be a lie about the provider.
        let decoded = try JSONCoders.makeDecoder().decode(
            VerifyIdentityResponse.self,
            from: Data(#"{"message":"ok"}"#.utf8)
        )
        XCTAssertTrue(decoded.isVerified)

        let explicit = try JSONCoders.makeDecoder().decode(
            VerifyIdentityResponse.self,
            from: Data(#"{"verified":false}"#.utf8)
        )
        XCTAssertFalse(explicit.isVerified, "an explicit false is still respected")
    }

    // MARK: - organizations (Bearer — corrected 2026-09-09, G25)

    func test_givenOrganizations_whenBuilt_thenUsesBearerAuth() {
        // CORRECTED: this route was modelled as session-only per decision
        // 0001. A raw `Authorization: Bearer` request with no cookie jar
        // returns HTTP 200 live, and the published OpenAPI document marks the
        // operation `x-auth-type: sync-token`.
        let request = User.organizations()
        XCTAssertEqual(request.path, "/api/user/organizations")
        XCTAssertEqual(request.auth, .bearer)
    }

    func test_givenRoleFilter_whenOrganizationsBuilt_thenSendsRoleQuery() {
        // The OpenAPI document declares an optional `role` query parameter.
        let request = User.organizations(role: "owner")
        let sent = request.query.filter { $0.value != nil }
        XCTAssertEqual(sent.map(\.name), ["role"])
        XCTAssertEqual(sent.first?.value, "owner")
    }

    func test_givenNoRoleFilter_whenOrganizationsBuilt_thenOmitsRoleQuery() {
        // Boundary: a nil filter must not put an empty `?role=` on the wire.
        // A nil filter leaves the item valueless, and valueless items are
        // dropped when the URL is built — no empty `?role=` on the wire.
        let request = User.organizations()
        XCTAssertTrue(request.query.filter { $0.value != nil }.isEmpty)
    }

    func test_givenOrganizationsEnvelope_whenSent_thenDecodesRoleAndMetadata() async throws {
        // Happy path over the **bearer** transport, with the membership
        // context fields the live route actually returns.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"""
        {"organizations":[{"id":"o1","name":"Acme","slug":"acme","description":"x",
          "avatar":null,"isPublic":true,"isSystem":false,
          "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z",
          "deletedAt":null,"role":"admin","joinedAt":"2026-02-01T00:00:00.000Z",
          "userRole":"admin","memberCount":3}]}
        """#))

        let response = try await client.send(User.organizations())
        XCTAssertEqual(response.organizations.first?.role, "admin")
        XCTAssertEqual(response.organizations.first?.name, "Acme")
        XCTAssertEqual(response.organizations.first?.userRole, "admin")
        XCTAssertEqual(response.organizations.first?.memberCount, 3)
        XCTAssertEqual(response.organizations.first?.isSystem, false)
    }

    func test_givenSystemOrgRow_whenSent_thenDecodesIsSystemTrue() async throws {
        // "The Public" is the row the leave rule must recognise.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"""
        {"organizations":[{"id":"00000000-0000-0000-0000-000000000001",
          "name":"The Public","slug":"the-public","isPublic":true,"isSystem":true,
          "role":"member","memberCount":22}]}
        """#))

        let response = try await client.send(User.organizations())
        XCTAssertEqual(response.organizations.first?.isSystem, true)
    }

    func test_givenOrganizationsFailure_whenSent_thenThrowsForbidden() async throws {
        // Upstream API failure on the bearer transport.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"error":"No access"}"#, status: 403))
        do {
            _ = try await client.send(User.organizations())
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "No access"))
        }
    }

    // MARK: - joinOrganization (G25)

    func test_givenOrganizationId_whenJoinBuilt_thenPostsOrganizationIdBody() throws {
        // Happy path: the join verb + body, confirmed from the shipped web
        // client and the OpenAPI document (never exercised as a live write).
        let request = User.joinOrganization(organizationId: "org_1")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/user/organizations")
        XCTAssertEqual(request.auth, .bearer)
        let body = try encodedBody(request)
        XCTAssertEqual(body["organizationId"] as? String, "org_1")
        XCTAssertEqual(body.count, 1, "The join body carries only organizationId")
    }

    // MARK: - update

    func test_givenProfilePatch_whenUpdateBuilt_thenPatchesOnlySetFields() throws {
        // Happy path + boundary: nil fields omitted.
        // PATCH, not POST — POST is 405 live, which is why Settings ▸ Preferences
        // never saved (work-consolidation.md §1c · V2).
        let request = User.update(UpdateUserRequest(displayName: "New Name", bio: nil))
        XCTAssertEqual(request.method, .patch)
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

    // MARK: - View Preferences body (G35 / issue #43)

    func test_givenViewPreferences_whenUpdateBuilt_thenEncodesTheWebsFourKeys() throws {
        // Happy path: the exact body the web's own "View Preferences" card
        // PATCHes, verified against the live bundle 2026-09-09.
        let request = User.update(UpdateUserRequest(
            messagesPerPage: 15,
            viewingPreference: "followers_only",
            showPreviews: false,
            notificationTrayLimit: 35
        ))

        let body = try encodedBody(request)
        XCTAssertEqual(body["messagesPerPage"] as? Int, 15)
        XCTAssertEqual(body["viewingPreference"] as? String, "followers_only")
        XCTAssertEqual(body["showPreviews"] as? Bool, false)
        XCTAssertEqual(body["notificationTrayLimit"] as? Int, 35)
    }

    func test_givenNoTrayLimit_whenUpdateBuilt_thenOmitsItSoItIsNeverClobbered() throws {
        // Invalid-by-omission guard: patching an unrelated field must not send
        // `notificationTrayLimit: null` and wipe the account's stored value.
        let request = User.update(UpdateUserRequest(displayName: "Ada"))

        let body = try encodedBody(request)
        XCTAssertNil(body["notificationTrayLimit"])
        XCTAssertNil(body["viewingPreference"])
    }

    func test_givenBoundaryTrayLimits_whenUpdateBuilt_thenEncodesThemVerbatim() throws {
        // Boundary: the request body is a faithful mirror — range enforcement
        // is the domain layer's job (`UserSettings` clamps), not the DTO's.
        for limit in [10, 40] {
            let body = try encodedBody(User.update(UpdateUserRequest(notificationTrayLimit: limit)))
            XCTAssertEqual(body["notificationTrayLimit"] as? Int, limit)
        }
    }

    func test_givenValidPatch_whenUpdateSent_thenReturnsUpdatedUser() async throws {
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(userEnvelopeJSON))
        let response = try await client.send(User.update(UpdateUserRequest(displayName: "Ada")))
        XCTAssertEqual(response.user.username, "ada")
        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "PATCH")
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

    // MARK: - search (GET /api/users/search) — NW-1

    func test_givenQuery_whenSearchBuilt_thenTargetsSearchPathWithBearer() throws {
        let request = User.search(query: "ada", limit: 10)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/users/search")
        XCTAssertEqual(request.auth, .bearer)
        let qItems = request.query
        XCTAssertTrue(qItems.contains { $0.name == "q" && $0.value == "ada" })
        XCTAssertTrue(qItems.contains { $0.name == "limit" && $0.value == "10" })
    }

    func test_givenEmptyQuery_whenSearchBuilt_thenQParameterPresent() throws {
        let request = User.search(query: "", limit: nil)
        XCTAssertEqual(request.path, "/api/users/search")
        XCTAssertTrue(request.query.contains { $0.name == "q" && $0.value == "" })
    }

    // MARK: - lookup (GET /api/users/lookup) — NW-1

    func test_givenHandle_whenLookupBuilt_thenTargetsLookupPathWithBearer() throws {
        let request = User.lookup(handle: "ada")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/users/lookup")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertTrue(request.query.contains { $0.name == "handle" && $0.value == "ada" })
    }

    func test_givenEmptyHandle_whenLookupBuilt_thenHandleParameterPresent() throws {
        let request = User.lookup(handle: "")
        XCTAssertTrue(request.query.contains { $0.name == "handle" && $0.value == "" })
    }

    // MARK: - publicProfile (GET /api/users/{username}) — D2

    func test_givenPublicProfileBuilder_whenBuilt_thenGetsUsersPathWithBearer() {
        let request = User.publicProfile(username: "ada")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/users/ada")
        XCTAssertEqual(request.auth, .bearer)
    }

    func test_givenProfileBody_whenPublicProfileSent_thenDecodesRichFields() async throws {
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"""
        {"id":"u1","username":"ada","displayName":"Ada","avatar":null,"headerImage":null,
         "bio":"hi","joinedAt":"2026-03-23T23:23:59.755Z","isPrivate":false,
         "followerCount":3,"followingCount":1,"publicMessageCount":10,"publicListCount":0}
        """#))

        let profile = try await client.send(User.publicProfile(username: "ada"))

        XCTAssertEqual(profile.id, "u1")
        XCTAssertEqual(profile.followerCount, 3)
        XCTAssertEqual(profile.bio, "hi")
    }
}

private struct AnyEncodableUserProbe: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { self._encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
