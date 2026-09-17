import Foundation
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
        /// The encoded JSON body, when the request carried one.
        ///
        /// Recorded so a test can assert the **shape** that goes on the wire,
        /// not only that a call was made. Without it, `create(…)` sending its
        /// schema as a string rather than an object was untestable at this
        /// layer — and the server rejects the string outright (GitHub #85).
        let body: Data?
    }

    private var outcomes: [Outcome] = []
    private(set) var recorded: [RecordedRequest] = []

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
        // Encoded with the client's own encoder so key naming and date strategy
        // match what really goes out; a body that fails to encode is recorded as
        // `nil` rather than failing the recording.
        var bodyData: Data?
        if case .json(let payload)? = request.body {
            bodyData = try? JSONCoders.makeEncoder().encode(payload)
        } else if case .raw(let data, _)? = request.body {
            bodyData = data
        }
        recorded.append(
            RecordedRequest(
                method: request.method.rawValue,
                path: request.path,
                query: query,
                body: bodyData
            )
        )
    }
}
