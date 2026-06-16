import XCTest
@testable import InterlinedKit

private struct Greeting: Codable, Sendable, Equatable {
    let hello: String
}

final class APIClientTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(),
        sessionTransport: StubHTTPDataTransport = StubHTTPDataTransport(),
        retryPolicy: RetryPolicy = .none
    ) -> (APIClient, StubHTTPDataTransport, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: sessionTransport,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(
            baseURL: baseURL,
            transport: transport,
            authTransport: auth,
            retryPolicy: retryPolicy
        )
        return (client, transport, sessionTransport)
    }

    // MARK: - Happy path

    func test_givenValid200Response_whenSent_thenDecodesBody() async throws {
        // Given
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"hello":"world"}"#))

        let request = Request<Greeting>(
            method: .get,
            path: "/api/test",
            auth: .none
        )

        // When
        let result = try await client.send(request)

        // Then
        XCTAssertEqual(result, Greeting(hello: "world"))
        let received = await transport.received
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].url?.absoluteString, "https://stub.local/api/test")
        XCTAssertEqual(received[0].httpMethod, "GET")
    }

    func test_givenBearerToken_whenSent_thenAttachesAuthorizationHeader() async throws {
        // Given — invalid input class: a Bearer request without a token still
        // sends (header simply omitted); with a token, header is attached.
        let tokenStore = InMemoryTokenStore(initial: "il_tok_abc")
        let (client, transport, _) = makeClient(tokenStore: tokenStore)
        await transport.enqueue(.json(#"{"hello":"hi"}"#))

        // When
        _ = try await client.send(Request<Greeting>(method: .get, path: "/api/me"))

        // Then
        let received = await transport.received
        XCTAssertEqual(
            received[0].value(forHTTPHeaderField: "Authorization"),
            "Bearer il_tok_abc"
        )
    }

    func test_givenJSONBody_whenSent_thenEncodesAndSetsContentType() async throws {
        // Given
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json("{}"))

        let payload = Greeting(hello: "there")
        let request = Request<EmptyResponse>(
            method: .post,
            path: "/api/echo",
            body: .json(payload),
            auth: .none
        )

        // When
        try await client.sendVoid(request)

        // Then
        let received = await transport.received
        XCTAssertEqual(
            received[0].value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        let body = try XCTUnwrap(received[0].httpBody)
        let decoded = try JSONDecoder().decode(Greeting.self, from: body)
        XCTAssertEqual(decoded, payload)
    }

    // MARK: - Invalid input / decoding failure

    func test_givenMalformedJSON_whenSent_thenThrowsDecodingError() async throws {
        // Given
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json("{not json}"))

        // When / Then
        do {
            _ = try await client.send(Request<Greeting>(method: .get, path: "/api/x", auth: .none))
            XCTFail("Expected decoding failure")
        } catch let error as APIError {
            guard case .decoding(let type, _) = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
            XCTAssertEqual(type, "Greeting")
        }
    }

    // MARK: - API failure / non-2xx mapping

    func test_given403Response_whenSent_thenMapsToForbiddenWithServerMessage() async throws {
        // Given — API failure case: 403 with the canonical body shape.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"error":"Email not verified"}"#, status: 403))

        // When / Then
        do {
            _ = try await client.send(Request<Greeting>(method: .get, path: "/api/x", auth: .none))
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "Email not verified"))
        }
    }

    func test_given500Response_whenSent_thenMapsToHttpStatus() async throws {
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"error":"boom"}"#, status: 500))

        do {
            _ = try await client.send(Request<Greeting>(method: .get, path: "/x", auth: .none))
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - Empty / boundary cases

    func test_givenEmptyResponseBody_whenSendVoidCalled_thenSucceeds() async throws {
        // Given — boundary: 204 No Content with no body.
        let (client, transport, _) = makeClient()
        await transport.enqueue(.empty(status: 204))

        // When / Then — does not throw.
        try await client.sendVoid(
            Request<EmptyResponse>(method: .delete, path: "/api/x", auth: .none)
        )
        let received = await transport.received
        XCTAssertEqual(received.count, 1)
    }

    func test_givenTransportError_whenSent_thenWrapsAsTransportAPIError() async throws {
        // Given — boundary: the underlying transport throws (offline).
        let (client, transport, _) = makeClient()
        await transport.enqueueError(URLError(.notConnectedToInternet))

        do {
            _ = try await client.send(Request<Greeting>(method: .get, path: "/x", auth: .none))
            XCTFail("Expected transport error")
        } catch let error as APIError {
            guard case .transport = error else {
                return XCTFail("Expected .transport, got \(error)")
            }
        }
    }

    // MARK: - Query parameters

    func test_givenOptionalQueryItems_whenSent_thenSkipsNilParameters() async throws {
        let (client, transport, _) = makeClient()
        await transport.enqueue(.json(#"{"hello":"x"}"#))

        let request = Request<Greeting>(
            method: .get,
            path: "/api/messages",
            query: [
                .int("limit", 10),
                .int("offset", nil),         // skipped
                .bool("onlyMine", true),
                .string("tag", nil)           // skipped
            ],
            auth: .none
        )

        _ = try await client.send(request)

        let received = await transport.received
        let url = try XCTUnwrap(received[0].url)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains(URLQueryItem(name: "limit", value: "10")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "onlyMine", value: "true")))
    }

    // MARK: - Raw bytes for CSV exports

    func test_givenCSVBody_whenSendRawCalled_thenReturnsBytesAndContentType() async throws {
        // .session routes through the session transport per decision 0001.
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        let csv = Data("id,name\n1,alpha\n".utf8)
        await session.enqueue(.data(csv, headers: ["Content-Type": "text/csv"]))

        let (client, _, _) = makeClient(transport: base, sessionTransport: session)

        let request = Request<EmptyResponse>(
            method: .get,
            path: "/api/exports/messages",
            auth: .session
        )

        let (bytes, contentType) = try await client.sendRaw(request)
        XCTAssertEqual(bytes, csv)
        XCTAssertEqual(contentType, "text/csv")
    }
}
