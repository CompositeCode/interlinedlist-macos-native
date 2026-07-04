import XCTest
@testable import InterlinedKit

final class LiveSessionEstablisherTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeSUT(
        credentials: Credentials? = Credentials(email: "test@example.com", password: "s3cr3t"),
        transport: StubHTTPDataTransport = StubHTTPDataTransport()
    ) -> (LiveSessionEstablisher, StubHTTPDataTransport, InMemoryCredentialStore) {
        let store = InMemoryCredentialStore(initial: credentials)
        let sut = LiveSessionEstablisher(
            credentialStore: store,
            transport: transport,
            baseURL: baseURL
        )
        return (sut, transport, store)
    }

    // MARK: - Happy path

    func test_givenStoredCredentials_whenEstablishCalled_thenLoginRequestSentWithCorrectShape() async throws {
        // Given
        let transport = StubHTTPDataTransport()
        await transport.enqueue(.empty(status: 200))
        let (sut, _, _) = makeSUT(transport: transport)

        // When
        try await sut.establishIfNeeded()

        // Then — one request to /api/auth/login with the right method + body.
        let received = await transport.received
        XCTAssertEqual(received.count, 1)
        let req = received[0]
        XCTAssertEqual(req.url?.path, "/api/auth/login")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(req.httpBody)
        let decoded = try JSONDecoder().decode([String: String].self, from: body)
        XCTAssertEqual(decoded["email"], "test@example.com")
        XCTAssertEqual(decoded["password"], "s3cr3t")
    }

    func test_givenStoredCredentials_whenServerReturns204_thenSucceeds() async throws {
        // Given — boundary: some servers return 204 instead of 200 for login.
        let transport = StubHTTPDataTransport()
        await transport.enqueue(.empty(status: 204))
        let (sut, _, _) = makeSUT(transport: transport)

        // When / Then — no error
        try await sut.establishIfNeeded()
    }

    // MARK: - Invalid credentials

    func test_givenNoStoredCredentials_whenEstablishCalled_thenThrowsUnauthorized() async throws {
        // Given — the credential store is empty (user has not signed in).
        let transport = StubHTTPDataTransport()
        let (sut, _, _) = makeSUT(credentials: nil, transport: transport)

        // When / Then
        do {
            try await sut.establishIfNeeded()
            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        }
        // No network request should have been sent.
        let received = await transport.received
        XCTAssertEqual(received.count, 0)
    }

    func test_givenStoredCredentials_whenServerReturns401_thenThrowsUnauthorized() async throws {
        // Given — credentials are stale / wrong on the server side.
        let transport = StubHTTPDataTransport()
        await transport.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        let (sut, _, _) = makeSUT(transport: transport)

        // When / Then
        do {
            try await sut.establishIfNeeded()
            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        }
    }

    // MARK: - API failure

    func test_givenStoredCredentials_whenServerReturns500_thenThrowsHttpStatus() async throws {
        // Given — server error.
        let transport = StubHTTPDataTransport()
        await transport.enqueue(.json(#"{"error":"Internal Server Error"}"#, status: 500))
        let (sut, _, _) = makeSUT(transport: transport)

        // When / Then
        do {
            try await sut.establishIfNeeded()
            XCTFail("Expected httpStatus error")
        } catch let error as APIError {
            guard case .httpStatus(let code, _) = error else {
                return XCTFail("Expected .httpStatus, got \(error)")
            }
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: - Transport failure

    func test_givenStoredCredentials_whenTransportThrows_thenPropagatesError() async throws {
        // Given — network-level failure (DNS, TLS, socket reset).
        let transport = StubHTTPDataTransport()
        await transport.enqueueError(URLError(.notConnectedToInternet))
        let (sut, _, _) = makeSUT(transport: transport)

        // When / Then — the raw URLError propagates (not wrapped).
        do {
            try await sut.establishIfNeeded()
            XCTFail("Expected transport error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
    }
}
