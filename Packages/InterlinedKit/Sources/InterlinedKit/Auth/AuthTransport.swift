import Foundation
import os

/// The transport-level auth seam that implements **decision 0001**.
///
/// `AuthTransport` is the only place in the kit that knows *how* a request
/// must be authenticated. It takes a `URLRequest`, the per-request
/// `AuthRequirement` hint, and the base `HTTPDataTransport`, and:
///
/// 1. For `.none` — sends the request unmodified.
/// 2. For `.bearer` (default for ~98 endpoints) — attaches
///    `Authorization: Bearer <token>` from the `TokenStore`.
/// 3. For `.session` (the allowlist: `/api/user/identities`,
///    `/api/user/organizations`, `/api/exports/*`) — lazily establishes a
///    cookie session via `POST /api/auth/login` (handled by an injected
///    `SessionEstablisher`), then re-executes through the cookie-bearing
///    transport. Bearer-only users who never hit the allowlist never pay
///    the login round-trip.
///
/// The 401 safety net (re-try a Bearer 401 once through the session
/// transport) lives in `APIClient`; `AuthTransport` simply honours whatever
/// requirement it is handed for a given call.
public protocol AuthTransport: Sendable {
    /// Executes `request` according to `auth`. The `base` transport is the
    /// underlying `HTTPDataTransport`, which the auth transport may use for
    /// Bearer/none and *may swap out* for `.session` (the session transport
    /// owns its own cookie-bearing `URLSession`).
    func execute(
        _ request: URLRequest,
        auth: AuthRequirement,
        base: HTTPDataTransport
    ) async throws -> (Data, HTTPURLResponse)
}

// MARK: - SessionEstablisher

/// Performs the lazy `POST /api/auth/login` step for the session-only
/// allowlist. Injected into `DefaultAuthTransport` so tests can stub it
/// without ever issuing a real network request.
public protocol SessionEstablisher: Sendable {
    /// Ensures a valid session cookie is established on the session
    /// transport's cookie storage. Throws on failure (typically 401 — bad
    /// credentials — surfaced as `APIError.unauthorized`).
    func establishIfNeeded() async throws
}

// MARK: - DefaultAuthTransport

/// Production implementation of `AuthTransport`.
///
/// The `sessionTransport` is a separate `HTTPDataTransport` that owns its
/// own cookie storage; production builds wire it to a `URLSession` whose
/// `URLSessionConfiguration.httpCookieStorage` is set to a private
/// `HTTPCookieStorage` instance. Tests inject a deterministic stub.
public actor DefaultAuthTransport: AuthTransport {

    private let tokenStore: TokenStore
    private let sessionTransport: HTTPDataTransport
    private let sessionEstablisher: SessionEstablisher
    private var sessionEstablished: Bool = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.interlinedlist.kit",
        category: "AuthTransport"
    )

    public init(
        tokenStore: TokenStore,
        sessionTransport: HTTPDataTransport,
        sessionEstablisher: SessionEstablisher
    ) {
        self.tokenStore = tokenStore
        self.sessionTransport = sessionTransport
        self.sessionEstablisher = sessionEstablisher
    }

    public func execute(
        _ request: URLRequest,
        auth: AuthRequirement,
        base: HTTPDataTransport
    ) async throws -> (Data, HTTPURLResponse) {
        switch auth {
        case .none:
            return try await base.data(for: request)

        case .bearer:
            var request = request
            if let token = try tokenStore.read() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await base.data(for: request)

        case .session:
            if !sessionEstablished {
                try await sessionEstablisher.establishIfNeeded()
                sessionEstablished = true
            }
            return try await sessionTransport.data(for: request)
        }
    }

    /// Drops the cached "session established" flag — used after sign-out so
    /// the next session-only request re-authenticates.
    public func invalidateSession() {
        sessionEstablished = false
    }
}

// MARK: - NullSessionEstablisher

/// A session establisher that does nothing. Useful for tests that never
/// exercise the `.session` path, and for builds that haven't wired the real
/// session login yet.
public struct NullSessionEstablisher: SessionEstablisher {
    public init() {}
    public func establishIfNeeded() async throws {}
}
