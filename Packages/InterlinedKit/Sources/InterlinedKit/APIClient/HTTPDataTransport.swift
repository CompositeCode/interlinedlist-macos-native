import Foundation

/// The narrow seam between `APIClient` and `URLSession`.
///
/// `APIClient` depends on this protocol, not on `URLSession` directly, so
/// unit tests can drive every code path without touching the network. The
/// real `URLSession` conforms via an extension; tests provide an in-memory
/// stub that returns canned `(Data, HTTPURLResponse)` pairs.
///
/// This is a pure data-fetch primitive — no auth, no decoding, no retry.
/// All of that lives in `APIClient` and `AuthTransport`.
public protocol HTTPDataTransport: Sendable {
    /// Performs the request and returns the raw bytes plus the HTTP response
    /// metadata. Any transport-level failure (DNS, TLS, timeout, connection
    /// reset, cancellation) is thrown.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPDataTransport {
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse) = try await self.data(for: request, delegate: nil)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(message: "Response was not an HTTPURLResponse")
        }
        return (data, http)
    }
}
