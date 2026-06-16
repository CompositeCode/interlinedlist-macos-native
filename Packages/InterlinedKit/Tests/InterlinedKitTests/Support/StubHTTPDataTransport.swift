import Foundation
@testable import InterlinedKit

/// Test seam: a deterministic `HTTPDataTransport` that returns canned
/// `(Data, HTTPURLResponse)` triples and records every received request.
///
/// State is isolated to an actor so the stub is safe under Swift 6 strict
/// concurrency. All test-facing methods are `async` — `XCTestCase`
/// methods are already `async throws` in this suite, so callers just
/// `await` the enqueue / snapshot calls.
actor StubHTTPDataTransport: HTTPDataTransport {

    struct StubbedResponse: Sendable {
        let status: Int
        let body: Data
        let headers: [String: String]

        static func json(_ json: String, status: Int = 200, headers: [String: String] = [:]) -> StubbedResponse {
            StubbedResponse(status: status, body: Data(json.utf8), headers: headers)
        }

        static func data(_ data: Data, status: Int = 200, headers: [String: String] = [:]) -> StubbedResponse {
            StubbedResponse(status: status, body: data, headers: headers)
        }

        static func empty(status: Int = 204) -> StubbedResponse {
            StubbedResponse(status: status, body: Data(), headers: [:])
        }
    }

    private var queue: [StubbedResponse] = []
    private(set) var received: [URLRequest] = []
    private var thrown: (any Error)?

    init() {}

    func enqueue(_ response: StubbedResponse) {
        queue.append(response)
    }

    func enqueueError(_ error: any Error) {
        thrown = error
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        received.append(request)
        if let err = thrown {
            thrown = nil
            throw err
        }
        guard !queue.isEmpty else {
            throw URLError(.cannotConnectToHost)
        }
        let next = queue.removeFirst()
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub.local/")!,
            statusCode: next.status,
            httpVersion: "HTTP/1.1",
            headerFields: next.headers
        )!
        return (next.body, http)
    }
}
