// APIFailureTests
//
// The opt-in error carrier (GitHub #103).
//
// `APIError` keeps only the decoded `{error}` string, which is enough for almost
// every failure and not enough for the few where the server answers a *question*
// — the list-schema destructive-change guard names the columns that still hold
// data, and the app-settings compare-and-set returns the current document.
//
// The most important property under test is the one that is easy to break by
// accident: **opting in must not change anything for callers that did not**.

import XCTest
@testable import InterlinedKit

final class APIFailureTests: XCTestCase {

    private let baseURL = URL(string: "https://example.test")!

    private func makeClient() -> (APIClient, StubHTTPDataTransport) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_test"),
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        return (APIClient(baseURL: baseURL, transport: transport, authTransport: auth), transport)
    }

    private struct Probe: Decodable, Sendable { let ok: Bool }

    /// The shape the list-schema guard actually answers with.
    private struct SchemaConflict: Decodable { let propertiesWithData: [String]? }

    // MARK: - Happy path

    func test_givenAFailureWithABody_whenCapturing_thenTheDetailsDecode() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Removing these columns would delete data.","code":"bad_request","propertiesWithData":["year","status"]}"#, status: 400))

        do {
            _ = try await client.sendCapturingFailure(Request<Probe>(method: .get, path: "/probe", auth: .bearer))
            XCTFail("expected a failure")
        } catch let failure as APIFailure {
            XCTAssertEqual(failure.httpStatusCode, 400)
            XCTAssertEqual(
                failure.details(as: SchemaConflict.self)?.propertiesWithData,
                ["year", "status"],
                "the structured half of the body is what this type exists for"
            )
        }
    }

    func test_givenAFailure_whenCapturing_thenTheMessageIsUnchangedFromAPIError() async throws {
        // Nothing regresses by opting in: an `APIFailure` that reaches generic
        // error-display code has to read exactly as the `APIError` would have.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"title required"}"#, status: 400))

        do {
            _ = try await client.sendCapturingFailure(Request<Probe>(method: .get, path: "/probe", auth: .bearer))
            XCTFail("expected a failure")
        } catch let failure as APIFailure {
            XCTAssertEqual(failure.underlyingError, .badRequest(serverMessage: "title required"))
            XCTAssertEqual(failure.localizedDescription, APIError.badRequest(serverMessage: "title required").localizedDescription)
        }
    }

    // MARK: - The property that must not break

    func test_givenTheSameFailure_whenSentNormally_thenItIsStillAPlainAPIError() async throws {
        // The transport raises `APIFailure` internally now so one code path
        // serves both entry points. Every caller that did not opt in must still
        // match `catch let error as APIError` — there are 420 such sites.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"title required","propertiesWithData":["year"]}"#, status: 400))

        do {
            _ = try await client.send(Request<Probe>(method: .get, path: "/probe", auth: .bearer))
            XCTFail("expected a failure")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "title required"))
        } catch {
            XCTFail("send(_:) must throw APIError, not \(type(of: error))")
        }
    }

    // MARK: - Invalid / absent details

    func test_givenABodyThatDoesNotMatch_whenDecodingDetails_thenItDegradesToNil() async throws {
        // A caller asking for details is asking an *optional* question. A decode
        // failure here must not mask the HTTP failure it is handling.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"nope"}"#, status: 400))

        do {
            _ = try await client.sendCapturingFailure(Request<Probe>(method: .get, path: "/probe", auth: .bearer))
            XCTFail("expected a failure")
        } catch let failure as APIFailure {
            XCTAssertNil(failure.details(as: SchemaConflict.self)?.propertiesWithData)
            XCTAssertEqual(failure.underlyingError, .badRequest(serverMessage: "nope"))
        }
    }

    func test_givenNoBodyAtAll_whenDecodingDetails_thenItIsNil() {
        // A transport failure never had a body to keep.
        let failure = APIFailure(underlyingError: .transport(message: "offline"), body: nil)
        XCTAssertNil(failure.details(as: SchemaConflict.self))
        XCTAssertNil(failure.httpStatusCode)
    }

    // MARK: - Boundary — a decode failure is not an HTTP failure

    func test_givenAnUndecodableSuccess_whenCapturing_thenItIsAPlainDecodingError() async throws {
        // A 200 whose body does not match is a client-side decode problem with
        // no server body to offer, so it surfaces as the `APIError.decoding` it
        // has always been rather than an `APIFailure` carrying nothing useful.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"unexpected":true}"#))

        do {
            _ = try await client.sendCapturingFailure(Request<Probe>(method: .get, path: "/probe", auth: .bearer))
            XCTFail("expected a failure")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("expected .decoding, got \(error)")
            }
        } catch {
            XCTFail("expected APIError.decoding, got \(type(of: error))")
        }
    }
}
