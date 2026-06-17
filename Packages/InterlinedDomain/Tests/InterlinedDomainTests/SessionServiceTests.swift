import XCTest
import InterlinedKit
@testable import InterlinedDomain

final class SessionServiceTests: XCTestCase {

    // MARK: - Restore

    func test_givenStoredTokenAndUserFetchSucceeds_whenRestoring_thenSignedIn() async throws {
        // Given
        let auth = StubAuthService(storedToken: true)
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.userEnvelope(username: "ada"))
        let service = SessionService(auth: auth, api: api)

        // When
        let state = try await service.restore()

        // Then
        XCTAssertTrue(state.isSignedIn)
        XCTAssertEqual(state.currentUser?.username, "ada")
    }

    func test_givenNoStoredToken_whenRestoring_thenSignedOut() async throws {
        // Given
        let auth = StubAuthService(storedToken: false)
        let api = StubAPIClient()
        let service = SessionService(auth: auth, api: api)

        // When
        let state = try await service.restore()

        // Then
        XCTAssertEqual(state, .signedOut)
        // And no user fetch was attempted.
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenStoredTokenButUserFetchFails_whenRestoring_thenThrows() async throws {
        // Given a token but a 401 on the user read (stale token).
        let auth = StubAuthService(storedToken: true)
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: nil))
        let service = SessionService(auth: auth, api: api)

        // When / Then
        do {
            _ = try await service.restore()
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: nil))
        }
    }

    // MARK: - Sign in / register

    func test_givenValidCredentials_whenSigningIn_thenFetchesUserAndSignsIn() async throws {
        // Given
        let auth = StubAuthService()
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.userEnvelope(username: "ada", customerStatus: "subscriber"))
        let service = SessionService(auth: auth, api: api)

        // When
        let user = try await service.signIn(email: "ada@example.com", password: "pw")

        // Then
        XCTAssertEqual(user.username, "ada")
        let state = await service.currentState()
        XCTAssertTrue(state.isSignedIn)
        let signedInCount = await auth.signedInCount
        XCTAssertEqual(signedInCount, 1)
    }

    func test_givenBadCredentials_whenSigningIn_thenThrowsAndStaysSignedOut() async throws {
        // Given the auth call itself fails.
        let auth = StubAuthService()
        await auth.primeError(.unauthorized(serverMessage: "bad login"))
        let api = StubAPIClient()
        let service = SessionService(auth: auth, api: api)

        // When / Then
        do {
            _ = try await service.signIn(email: "x", password: "y")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "bad login"))
        }
        let state = await service.currentState()
        XCTAssertEqual(state, .signedOut)
    }

    func test_givenNewAccount_whenRegistering_thenSignsIn() async throws {
        // Given
        let auth = StubAuthService()
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.userEnvelope(username: "newbie"))
        let service = SessionService(auth: auth, api: api)

        // When
        let user = try await service.register(email: "n@example.com", password: "pw", username: "newbie")

        // Then
        XCTAssertEqual(user.username, "newbie")
        let registeredCount = await auth.registeredCount
        XCTAssertEqual(registeredCount, 1)
    }

    // MARK: - Password reset

    func test_givenEmail_whenRequestingReset_thenForwardsToAuthService() async throws {
        // Given
        let auth = StubAuthService()
        let api = StubAPIClient()
        let service = SessionService(auth: auth, api: api)

        // When
        try await service.requestPasswordReset(email: "ada@example.com")

        // Then
        let lastResetEmail = await auth.lastResetEmail
        XCTAssertEqual(lastResetEmail, "ada@example.com")
    }

    func test_givenResetFailure_whenRequestingReset_thenThrows() async throws {
        // Given
        let auth = StubAuthService()
        await auth.primeError(.badRequest(serverMessage: "no such email"))
        let service = SessionService(auth: auth, api: StubAPIClient())

        // When / Then
        do {
            try await service.requestPasswordReset(email: "x")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "no such email"))
        }
    }

    // MARK: - Sign out

    func test_givenSignedIn_whenSigningOut_thenClearsTokenCacheAndState() async throws {
        // Given a signed-in session with a populated cache.
        let auth = StubAuthService(storedToken: true)
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.userEnvelope())
        let cache = InMemoryMessageStore()
        await cache.upsert([Message(from: sampleDTO(id: "m1"))])
        let service = SessionService(auth: auth, api: api, cache: cache)
        _ = try await service.restore()

        // When
        try await service.signOut()

        // Then — token cleared, cache cleared, state signed out.
        let signedOutCount = await auth.signedOutCount
        XCTAssertEqual(signedOutCount, 1)
        let cached = await cache.cachedMessage(id: "m1")
        XCTAssertNil(cached)
        let state = await service.currentState()
        XCTAssertEqual(state, .signedOut)
    }

    // MARK: - Observation

    func test_givenStream_whenSigningIn_thenStreamYieldsSignedOutThenSignedIn() async throws {
        // Given a subscriber to the state stream before sign-in.
        let auth = StubAuthService()
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.userEnvelope(username: "ada"))
        let service = SessionService(auth: auth, api: api)

        var iterator = service.states.makeAsyncIterator()
        let initial = await iterator.next()      // initial state on subscribe

        // When
        _ = try await service.signIn(email: "a", password: "b")
        let afterSignIn = await iterator.next()

        // Then
        XCTAssertEqual(initial, .signedOut)
        XCTAssertEqual(afterSignIn?.currentUser?.username, "ada")
    }

    // MARK: - Helpers

    private func sampleDTO(id: String) -> MessageDTO {
        MessageDTO(
            id: id,
            content: "hi",
            publiclyVisible: true,
            userId: "u1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            digCount: 0,
            pushCount: 0,
            user: UserSummaryDTO(id: "u1", username: "ada"),
            dugByMe: false
        )
    }
}
