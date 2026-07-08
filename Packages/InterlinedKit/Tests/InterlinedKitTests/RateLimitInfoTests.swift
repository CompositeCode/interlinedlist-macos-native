import XCTest
@testable import InterlinedKit

// MARK: - RateLimitInfo.parse quartet

final class RateLimitInfoParseTests: XCTestCase {

    // MARK: Happy path

    func test_givenAllThreeHeaders_whenParsed_thenReturnsCompleteRateLimitInfo() {
        // Given — all three headers present with a Unix-epoch reset value.
        let epochSeconds: TimeInterval = 1_700_000_000
        let response = makeResponse(headers: [
            "RateLimit-Limit":     "100",
            "RateLimit-Remaining": "42",
            "RateLimit-Reset":     "\(Int(epochSeconds))"
        ])

        // When
        let info = RateLimitInfo.parse(from: response)

        // Then
        let expected = RateLimitInfo(
            limit: 100,
            remaining: 42,
            resetAt: Date(timeIntervalSince1970: epochSeconds)
        )
        XCTAssertEqual(info, expected)
    }

    // MARK: Invalid input

    func test_givenNonNumericLimitHeader_whenParsed_thenReturnsNil() {
        // Given — non-numeric limit should not crash or warn, just return nil.
        let response = makeResponse(headers: [
            "RateLimit-Limit":     "unlimited",
            "RateLimit-Remaining": "42"
        ])

        // When
        let info = RateLimitInfo.parse(from: response)

        // Then
        XCTAssertNil(info, "Non-numeric limit header must yield nil, not a crash or warning")
    }

    // MARK: Absent headers (the "no limit on this route" case)

    func test_givenNoRateLimitHeaders_whenParsed_thenReturnsNil() {
        // Given — a response from a route that emits no rate-limit headers at all.
        let response = makeResponse(headers: [:])

        // When
        let info = RateLimitInfo.parse(from: response)

        // Then — nil signals "no limit enforced", not an error.
        XCTAssertNil(info, "Absent headers must yield nil, not an error or warning")
    }

    // MARK: Boundary — reset header absent

    func test_givenLimitAndRemainingWithoutResetHeader_whenParsed_thenReturnsInfoWithNilResetAt() {
        // Given — only limit + remaining present; reset is optional.
        let response = makeResponse(headers: [
            "RateLimit-Limit":     "60",
            "RateLimit-Remaining": "0"
        ])

        // When
        let info = RateLimitInfo.parse(from: response)

        // Then — still a valid envelope; resetAt is nil.
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.limit, 60)
        XCTAssertEqual(info?.remaining, 0)
        XCTAssertNil(info?.resetAt, "Absent reset header must yield nil resetAt, not a crash")
    }
}

// MARK: - APIClient.sendWithRateLimitInfo quartet

final class APIClientSendWithRateLimitInfoTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport()
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(),
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(
            baseURL: baseURL,
            transport: transport,
            authTransport: auth
        )
        return (client, transport)
    }

    // MARK: Happy path

    func test_given200ResponseWithAllRateLimitHeaders_whenSendWithRateLimitInfoCalled_thenReturnsDecodedResponseAndInfo() async throws {
        // Given
        let (client, transport) = makeClient()
        let epochSeconds: TimeInterval = 1_700_000_000
        await transport.enqueue(.json(
            #"{"hello":"world"}"#,
            headers: [
                "RateLimit-Limit":     "100",
                "RateLimit-Remaining": "99",
                "RateLimit-Reset":     "\(Int(epochSeconds))"
            ]
        ))

        let request = Request<Greeting>(method: .get, path: "/api/test", auth: .none)

        // When
        let (response, info) = try await client.sendWithRateLimitInfo(request)

        // Then
        XCTAssertEqual(response, Greeting(hello: "world"))
        XCTAssertEqual(info?.limit, 100)
        XCTAssertEqual(info?.remaining, 99)
        XCTAssertEqual(info?.resetAt, Date(timeIntervalSince1970: epochSeconds))
    }

    // MARK: Invalid input — non-numeric header must not crash

    func test_given200ResponseWithMalformedRateLimitHeader_whenSendWithRateLimitInfoCalled_thenReturnsNilInfo() async throws {
        // Given — header value is non-numeric; parse must be silent and return nil.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(
            #"{"hello":"graceful"}"#,
            headers: ["RateLimit-Limit": "many", "RateLimit-Remaining": "some"]
        ))

        let request = Request<Greeting>(method: .get, path: "/api/test", auth: .none)

        // When
        let (response, info) = try await client.sendWithRateLimitInfo(request)

        // Then — body decoded successfully; rate-limit info is nil (no crash, no warning).
        XCTAssertEqual(response.hello, "graceful")
        XCTAssertNil(info, "Non-numeric headers must yield nil info, not an error")
    }

    // MARK: Upstream API failure — 429 still throws, not silently swallowed

    func test_given429Response_whenSendWithRateLimitInfoCalled_thenThrowsRateLimited() async throws {
        // Given
        let (client, transport) = makeClient()
        await transport.enqueue(.json(
            #"{"error":"Too many requests"}"#,
            status: 429,
            headers: ["Retry-After": "30"]
        ))

        let request = Request<Greeting>(method: .post, path: "/api/messages", auth: .none)

        // When / Then
        do {
            _ = try await client.sendWithRateLimitInfo(request)
            XCTFail("Expected .rateLimited to be thrown")
        } catch let error as APIError {
            guard case .rateLimited(let msg, let retryAfter) = error else {
                return XCTFail("Expected .rateLimited, got \(error)")
            }
            XCTAssertEqual(msg, "Too many requests")
            XCTAssertEqual(retryAfter, 30)
        }
    }

    // MARK: Boundary — route emits no rate-limit headers → nil, no warning

    func test_given200ResponseWithNoRateLimitHeaders_whenSendWithRateLimitInfoCalled_thenReturnsNilInfo() async throws {
        // Given — a typical GET route that never sends rate-limit headers.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"hello":"plain"}"#))  // no headers

        let request = Request<Greeting>(method: .get, path: "/api/lists", auth: .none)

        // When
        let (response, info) = try await client.sendWithRateLimitInfo(request)

        // Then — no headers → nil is the correct signal, not an error.
        XCTAssertEqual(response.hello, "plain")
        XCTAssertNil(info, "Absent rate-limit headers must yield nil, not an error or warning")
    }
}

// MARK: - Shared fixture

private struct Greeting: Codable, Sendable, Equatable {
    let hello: String
}

// MARK: - Helpers

private func makeResponse(headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://stub.local/api/test")!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}
