import Foundation
import os

// MARK: - APIClientProtocol

/// The abstraction every service in `InterlinedDomain` depends on. Concrete
/// implementations build a `URLRequest` from a `Request<…>`, apply auth
/// (Bearer or session per decision 0001), execute the request, and decode
/// the response into the declared type — mapping every failure mode to
/// `APIError`.
///
/// Three overloads cover the three response shapes we need:
///
/// - `send(_:)` decodes the body into `Response`.
/// - `sendVoid(_:)` for endpoints with no body or where the body is ignored.
/// - `sendRaw(_:)` returns the bytes; used for CSV export endpoints.
public protocol APIClientProtocol: Sendable {
    /// Executes a request and decodes its JSON body into `Response`.
    func send<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> Response

    /// Executes a request and discards the body. Used for endpoints that
    /// only meaningfully return a status code (some DELETEs, the dig
    /// toggle, etc.).
    func sendVoid<Response>(_ request: Request<Response>) async throws

    /// Executes a request and returns the raw bytes plus content type.
    /// Used for CSV export endpoints (`/api/exports/*`).
    func sendRaw<Response>(_ request: Request<Response>) async throws -> (Data, String?)
}

// MARK: - APIClient

/// Default `URLSession`-backed implementation of `APIClientProtocol`.
///
/// **Construction.** Inject every collaborator:
///
/// - `baseURL` — defaults to `https://interlinedlist.com`. Tests point this
///   at a stub host.
/// - `transport` — anything conforming to `HTTPDataTransport`. Defaults to
///   `URLSession.shared`; production code injects a configured session and
///   tests inject an in-memory stub.
/// - `authTransport` — applies the bearer header or cookie session per
///   decision 0001. Tests inject a no-op or controllable stub.
/// - `decoder` / `encoder` — shared `JSONCoders` configuration.
/// - `retryPolicy` — a single seam for 429 / transient backoff. Empty by
///   default (PLAN.md §8 — rate limits undocumented; the hook exists so
///   adding policy later is one-line).
public final class APIClient: APIClientProtocol {

    private let baseURL: URL
    private let transport: HTTPDataTransport
    private let authTransport: AuthTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let retryPolicy: RetryPolicy
    private let logger: Logger

    public init(
        baseURL: URL = URL(string: "https://interlinedlist.com")!,
        transport: HTTPDataTransport = URLSession.shared,
        authTransport: AuthTransport,
        decoder: JSONDecoder = JSONCoders.makeDecoder(),
        encoder: JSONEncoder = JSONCoders.makeEncoder(),
        retryPolicy: RetryPolicy = .none
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.authTransport = authTransport
        self.decoder = decoder
        self.encoder = encoder
        self.retryPolicy = retryPolicy
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.interlinedlist.kit",
            category: "APIClient"
        )
    }

    // MARK: APIClientProtocol

    public func send<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> Response {
        let (data, _) = try await performWithSafetyNet(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(
                type: String(describing: Response.self),
                message: error.localizedDescription
            )
        }
    }

    public func sendVoid<Response>(_ request: Request<Response>) async throws {
        _ = try await performWithSafetyNet(request)
    }

    public func sendRaw<Response>(_ request: Request<Response>) async throws -> (Data, String?) {
        let (data, response) = try await performWithSafetyNet(request)
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        return (data, contentType)
    }

    // MARK: - Execution

    /// Runs the request, applying:
    ///
    /// 1. The retry policy (currently a no-op, but the hook is here for 429).
    /// 2. The decision-0001 401 safety net: on an unexpected 401 to a Bearer
    ///    request, retry exactly once via the session transport. If that
    ///    second attempt is also 401, surface the 401.
    private func performWithSafetyNet<Response>(
        _ request: Request<Response>
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await performWithRetry(request, forceSession: false)
        } catch let error as APIError {
            // Safety net: a Bearer request that comes back 401 should
            // transparently try once via the session transport before we
            // give up. This catches future API drift in either direction.
            if case .unauthorized = error, request.auth == .bearer {
                logger.warning("Bearer request returned 401 — retrying via session transport")
                return try await performWithRetry(request, forceSession: true)
            }
            throw error
        }
    }

    private func performWithRetry<Response>(
        _ request: Request<Response>,
        forceSession: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            do {
                return try await performOnce(request, forceSession: forceSession)
            } catch let error as APIError {
                if let delay = retryPolicy.delay(error, attempt) {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
    }

    private func performOnce<Response>(
        _ request: Request<Response>,
        forceSession: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try buildURLRequest(request, forceSession: forceSession)
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await authTransport.execute(
                urlRequest,
                auth: forceSession ? .session : request.auth,
                base: transport
            )
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(message: error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw APIError.from(
                statusCode: response.statusCode,
                serverMessage: decodeServerMessage(from: data),
                retryAfter: parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
            )
        }
        return (data, response)
    }

    // MARK: - URLRequest assembly

    private func buildURLRequest<Response>(
        _ request: Request<Response>,
        forceSession: Bool
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(request.path.trimmingPathPrefix()),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.transport(message: "Could not assemble URL for \(request.path)")
        }
        // Force the path back: appendingPathComponent re-encodes slashes
        // in a way URLComponents doesn't like for /api/messages/{id}/replies.
        components.path = (baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path)
            + (request.path.hasPrefix("/") ? request.path : "/" + request.path)

        let urlQuery = request.query.compactMap { item -> URLQueryItem? in
            guard let value = item.value else { return nil }
            return URLQueryItem(name: item.name, value: value)
        }
        if !urlQuery.isEmpty {
            components.queryItems = urlQuery
        }

        guard let url = components.url else {
            throw APIError.transport(message: "Could not assemble URL for \(request.path)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        switch request.body {
        case .none:
            break
        case .json(let value):
            do {
                let data = try encoder.encode(AnyEncodable(value))
                urlRequest.httpBody = data
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw APIError.decoding(
                    type: "request body",
                    message: error.localizedDescription
                )
            }
        case .raw(let data, let contentType):
            urlRequest.httpBody = data
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        return urlRequest
    }

    // MARK: - Helpers

    private func decodeServerMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let body = try? decoder.decode(APIErrorBody.self, from: data) {
            return body.error
        }
        return nil
    }

    private func parseRetryAfter(_ value: String?) -> TimeInterval? {
        guard let value, let seconds = TimeInterval(value) else { return nil }
        return seconds
    }
}

// MARK: - AnyEncodable

/// Erases `any Encodable & Sendable` so we can encode it through `JSONEncoder`.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) {
        self._encode = wrapped.encode
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - String helpers

private extension String {
    /// `appendingPathComponent` doesn't behave well when the component
    /// starts with `/`. We use a manual join in `buildURLRequest`, but keep
    /// this helper so the intermediate URL still parses on every path.
    func trimmingPathPrefix() -> String {
        hasPrefix("/") ? String(dropFirst()) : self
    }
}
