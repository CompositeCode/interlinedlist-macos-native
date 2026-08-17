import XCTest
@testable import InterlinedKit

/// BDD tests for the Limits endpoint (work-consolidation.md G14).
final class LimitsEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_abc")
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    // MARK: - Builder shape

    func test_givenLimitsBuilder_whenConstructed_thenUsesExpectedMethodPathAuth() {
        let request = Limits.get()
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/limits")
        XCTAssertEqual(request.auth, .bearer)
        XCTAssertTrue(request.query.isEmpty)
    }

    // MARK: - Happy path

    func test_givenFullBody_whenSent_thenDecodesEveryField() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "media": { "image": { "maxBytes": 1468006, "maxPixels": 1200,
                                "acceptedFormats": ["jpeg","png","gif","webp"] },
                     "video": { "maxBytes": 3145728, "acceptedFormats": ["mp4","mov"] } },
          "message": { "maxContentLength": 5000 } }
        """#))

        let dto = try await client.send(Limits.get())

        XCTAssertEqual(dto.media?.image?.maxBytes, 1_468_006)
        XCTAssertEqual(dto.media?.image?.maxPixels, 1200)
        XCTAssertEqual(dto.media?.image?.acceptedFormats, ["jpeg", "png", "gif", "webp"])
        XCTAssertEqual(dto.media?.video?.maxBytes, 3_145_728)
        XCTAssertEqual(dto.media?.video?.acceptedFormats, ["mp4", "mov"])
        XCTAssertEqual(dto.message?.maxContentLength, 5000)
    }

    // MARK: - Tolerant decoding

    func test_givenPartialBody_whenSent_thenMissingSubObjectsAreNil() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "message": { "maxContentLength": 4000 } }"#))

        let dto = try await client.send(Limits.get())

        XCTAssertNil(dto.media)
        XCTAssertEqual(dto.message?.maxContentLength, 4000)
    }

    // MARK: - API failure

    func test_givenServerError_whenSent_thenThrowsHttpStatus() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"boom"}"#, status: 500))

        do {
            _ = try await client.send(Limits.get())
            XCTFail("Expected httpStatus")
        } catch let error as APIError {
            if case .httpStatus(let code, _) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected .httpStatus, got \(error)")
            }
        }
    }
}
