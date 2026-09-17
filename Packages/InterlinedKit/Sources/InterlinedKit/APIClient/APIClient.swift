import Foundation

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

    /// Executes a request and, on an HTTP failure, throws an ``APIFailure``
    /// **carrying the response body** instead of discarding it (GitHub #103).
    ///
    /// Opt-in on purpose. `APIError` keeps only the decoded `{error}` string,
    /// which is all the UI needs for almost every failure — and not enough for
    /// the few where the server answers a *question*: the list-schema
    /// destructive-change guard names the columns that still hold data, and the
    /// app-settings compare-and-set returns the current document on a conflict.
    ///
    /// Only callers that need the body use this. Everything else keeps throwing
    /// plain `APIError`, so the 420 existing pattern-match sites are untouched.
    ///
    /// - Important: this throws `APIFailure`, **not** `APIError`. A caller that
    ///   opts in must catch accordingly; `APIFailure.underlyingError` carries the
    ///   `APIError` for anything that only wants the status or the message.
    func sendCapturingFailure<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> Response

    /// Executes a request, decodes its JSON body into `Response`, and returns
    /// any rate-limit metadata extracted from the response headers.
    ///
    /// Returns `nil` for `rateLimitInfo` when the route does not emit
    /// `RateLimit-Limit` / `RateLimit-Remaining` / `RateLimit-Reset` headers.
    /// Callers **must** treat `nil` as "no limit enforced on this route" and
    /// must not error, warn, or stall when the headers are absent.
    ///
    /// A default implementation is provided via a protocol extension; it calls
    /// `send(_:)` and returns `nil` for rate-limit info. Override in concrete
    /// types (e.g. `APIClient`) to provide actual header extraction.
    func sendWithRateLimitInfo<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> (Response, RateLimitInfo?)
}

// MARK: - Default implementation

extension APIClientProtocol {

    /// Default for conformers that cannot capture a response body — primarily
    /// stubs and fakes.
    ///
    /// It wraps whatever `send(_:)` threw with `body: nil`, so an opted-in
    /// caller still sees an `APIFailure` and its `details(as:)` simply answers
    /// `nil`. That is the correct degradation: "no details available" is a real
    /// state (a transport failure has no body either), so a stub that cannot
    /// supply one is not lying.
    ///
    /// A non-`APIError` failure is rethrown untouched rather than wrapped —
    /// a `CancellationError` is not an HTTP failure and must not start looking
    /// like one.
    public func sendCapturingFailure<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> Response {
        do {
            return try await send(request)
        } catch let error as APIError {
            throw APIFailure(underlyingError: error, body: nil)
        }
    }

    /// Conformers that do not need real rate-limit header extraction — primarily
    /// stubs and fakes — get this default which calls `send(_:)` and returns
    /// `nil`, correctly signalling "no limit enforced".
    public func sendWithRateLimitInfo<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> (Response, RateLimitInfo?) {
        (try await send(request), nil)
    }
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
    private let appLog: AppLog

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
        self.appLog = AppLog(category: "APIClient")
    }

    // MARK: APIClientProtocol

    public func send<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> Response {
        let (data, _) = try await unwrappingFailure { try await performWithSafetyNet(request) }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            // Log the full decoder detail (coding path / key) with the request
            // path — the user only ever sees `APIError.userFacingMessage`.
            let detail = String(reflecting: error)
            appLog.error("Decode failed [\(request.path)] type=\(String(describing: Response.self)): \(detail)")
            throw APIError.decoding(
                type: String(describing: Response.self),
                message: detail
            )
        }
    }

    public func sendVoid<Response>(_ request: Request<Response>) async throws {
        _ = try await unwrappingFailure { try await performWithSafetyNet(request) }
    }

    public func sendCapturingFailure<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> Response {
        // Deliberately does NOT unwrap: this is the one entry point whose
        // caller asked for the body.
        let (data, _) = try await performWithSafetyNet(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            let detail = String(reflecting: error)
            appLog.error("Decode failed [\(request.path)] type=\(String(describing: Response.self)): \(detail)")
            // A *decode* failure is not an HTTP failure and has no server body
            // to offer, so it surfaces as the plain `APIError` it has always
            // been rather than an `APIFailure` with nothing in it.
            throw APIError.decoding(
                type: String(describing: Response.self),
                message: detail
            )
        }
    }

    /// Runs `work` and flattens any `APIFailure` back to its `APIError`.
    ///
    /// The transport now raises the richer error so one code path serves both
    /// entry points. Every caller that did not opt in must still see exactly
    /// what it saw before — `catch let error as APIError` has to keep matching —
    /// so the unwrap happens here rather than at 420 call sites.
    private func unwrappingFailure<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let failure as APIFailure {
            throw failure.underlyingError
        }
    }

    public func sendRaw<Response>(_ request: Request<Response>) async throws -> (Data, String?) {
        let (data, response) = try await unwrappingFailure { try await performWithSafetyNet(request) }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        return (data, contentType)
    }

    public func sendWithRateLimitInfo<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> (Response, RateLimitInfo?) {
        let (data, response) = try await unwrappingFailure { try await performWithSafetyNet(request) }
        do {
            let decoded = try decoder.decode(Response.self, from: data)
            // RateLimitInfo.parse returns nil when headers are absent —
            // that is the correct "no limit on this route" signal.
            return (decoded, RateLimitInfo.parse(from: response))
        } catch {
            // Log the full decoder detail (coding path / key) with the request
            // path — the user only ever sees `APIError.userFacingMessage`.
            let detail = String(reflecting: error)
            appLog.error("Decode failed [\(request.path)] type=\(String(describing: Response.self)): \(detail)")
            throw APIError.decoding(
                type: String(describing: Response.self),
                message: detail
            )
        }
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
        } catch let failure as APIFailure {
            // Safety net: a Bearer request that comes back 401 should
            // transparently try once via the session transport before we
            // give up. This catches future API drift in either direction.
            //
            // Matched on `underlyingError`, because the transport now raises
            // `APIFailure` so the response body survives to a caller that asked
            // for it (GitHub #103). The `APIFailure` is rethrown intact rather
            // than flattened — flattening here would drop the body before
            // `sendCapturingFailure` ever saw it, which is the entire point of
            // the type.
            if case .unauthorized = failure.underlyingError, request.auth == .bearer {
                appLog.warning("Bearer request returned 401 [\(request.path)] — retrying via session transport")
                return try await performWithRetry(request, forceSession: true)
            }
            throw failure
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
            } catch let failure as APIFailure {
                // Same reasoning as the safety net above: the retry policy asks
                // about the `APIError`, and the `APIFailure` is rethrown whole so
                // the body reaches whoever asked for it.
                if let delay = retryPolicy.delay(failure.underlyingError, attempt) {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw failure
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
        } catch is CancellationError {
            // Cooperative task cancellation (a SwiftUI `.task` torn down on
            // view teardown / navigation) is not a network failure. Propagate
            // it as-is so callers can ignore it instead of surfacing a
            // spurious "Network error: cancelled" banner.
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // URLSession's async API reports task cancellation as
            // `URLError(.cancelled)`. Normalise it to `CancellationError` so
            // the `.cancelled` signal survives the boundary (it would
            // otherwise be flattened into `.transport(message: "cancelled")`
            // and be indistinguishable from a genuine transport failure).
            throw CancellationError()
        } catch {
            appLog.error("Transport failed [\(request.path)]: \(String(reflecting: error))")
            throw APIError.transport(message: error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            let serverMessage = decodeServerMessage(from: data)
            appLog.notice("HTTP \(response.statusCode) [\(request.path)]: \(serverMessage ?? "no server message")")
            let apiError = APIError.from(
                statusCode: response.statusCode,
                serverMessage: serverMessage,
                retryAfter: parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
            )
            // The body is kept alongside the error so `sendCapturingFailure`
            // can hand it to a caller that asked for it (GitHub #103).
            // `send(_:)` unwraps this back to a plain `APIError`, so every
            // existing caller is unaffected — the richer error never leaks into
            // a code path that did not opt in.
            throw APIFailure(underlyingError: apiError, body: data)
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
