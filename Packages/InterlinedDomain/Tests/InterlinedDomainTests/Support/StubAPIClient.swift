import Foundation
import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// Deterministic `APIClientProtocol` stub for domain-service tests.
///
/// Mirrors the kit's stub style (an `actor` for Swift 6 safety) but operates at
/// the `APIClientProtocol` seam the services actually depend on, rather than at
/// the `HTTPDataTransport` level. Each call to `send` / `sendRaw` / `sendVoid`
/// pops the next queued outcome; the stub records every request path so tests
/// can assert query mapping (scope → onlyMine, tag, limit/offset).
///
/// Outcomes carry raw JSON `Data`. `send` decodes it with the shared kit
/// decoder (so dates parse exactly as production does); `sendRaw` returns the
/// bytes untouched — which is the path paginated timeline reads take.
actor StubAPIClient: APIClientProtocol {

    /// What the next call should do.
    enum Outcome: Sendable {
        case json(Data)
        case failure(APIError)
    }

    /// A recorded outbound request, reduced to the fields tests assert on.
    struct RecordedRequest: Sendable, Equatable {
        let method: String
        let path: String
        let query: [String: String]
    }

    private var outcomes: [Outcome] = []
    private(set) var recorded: [RecordedRequest] = []

    /// The encoded `.json` request bodies, in send order, encoded with the same
    /// kit encoder production uses.
    ///
    /// Added for the G40 saved-views tests: `config` must go out as a JSON
    /// *object* (the OpenAPI request body wrongly declares it a string), and
    /// `PUT` replaces the config whole, so "what exactly did we send" is a
    /// correctness question at the service seam and not only at the transport
    /// seam. `RecordedRequest` is left untouched so its `Equatable` conformance
    /// keeps working for the suites that compare whole requests.
    private(set) var sentBodies: [Data] = []

    init() {}

    // MARK: Programming the stub

    func enqueue(json: String) {
        outcomes.append(.json(Data(json.utf8)))
    }

    func enqueue(data: Data) {
        outcomes.append(.json(data))
    }

    func enqueue(failure: APIError) {
        outcomes.append(.failure(failure))
    }

    // MARK: APIClientProtocol

    func send<Response: Decodable & Sendable>(_ request: Request<Response>) async throws -> Response {
        let data = try nextData(for: request)
        do {
            return try JSONCoders.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(type: String(describing: Response.self), message: error.localizedDescription)
        }
    }

    func sendVoid<Response>(_ request: Request<Response>) async throws {
        _ = try nextData(for: request)
    }

    func sendRaw<Response>(_ request: Request<Response>) async throws -> (Data, String?) {
        let data = try nextData(for: request)
        return (data, "application/json")
    }

    // MARK: - Internals

    private func nextData<Response>(for request: Request<Response>) throws -> Data {
        record(request)
        guard !outcomes.isEmpty else {
            throw APIError.transport(message: "StubAPIClient: no queued outcome for \(request.path)")
        }
        switch outcomes.removeFirst() {
        case .json(let data):
            return data
        case .failure(let error):
            throw error
        }
    }

    private func record<Response>(_ request: Request<Response>) {
        var query: [String: String] = [:]
        for item in request.query where item.value != nil {
            query[item.name] = item.value
        }
        recorded.append(
            RecordedRequest(method: request.method.rawValue, path: request.path, query: query)
        )
        if case .json(let value) = request.body,
           let encoded = try? JSONCoders.makeEncoder().encode(value) {
            sentBodies.append(encoded)
        }
    }

}

// MARK: - Body assertions

extension XCTestCase {
    /// The most recent `.json` body the stub encoded, as a dictionary.
    ///
    /// Lives on `XCTestCase` rather than on the actor because `[String: Any]`
    /// is not `Sendable` and so cannot cross an actor boundary under Swift 6 —
    /// the bytes (`sentBodies`) cross instead, and the parse happens test-side.
    func lastSentJSON(_ api: StubAPIClient) async throws -> [String: Any] {
        let bodies = await api.sentBodies
        let data = try XCTUnwrap(bodies.last, "No JSON request body was recorded")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Recorded request body was not a JSON object"
        )
    }
}
