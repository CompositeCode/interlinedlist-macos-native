import Foundation

// MARK: - DTOs

/// Payload for `POST /api/auth/sync-token` and `POST /api/auth/login`.
public struct CredentialsRequest: Encodable, Sendable, Equatable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

/// Response body for `POST /api/auth/sync-token`. The API returns the bearer
/// token under the `token` key (verified by the spike — see
/// `docs/spikes/auth-bearer-vs-session.md`).
public struct SyncTokenResponse: Decodable, Sendable, Equatable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

/// Payload for `POST /api/auth/register`.
public struct RegisterRequest: Encodable, Sendable, Equatable {
    public let email: String
    public let password: String
    public let username: String?

    public init(email: String, password: String, username: String? = nil) {
        self.email = email
        self.password = password
        self.username = username
    }
}

/// Payload for `POST /api/auth/password-reset/request`.
public struct PasswordResetRequest: Encodable, Sendable, Equatable {
    public let email: String

    public init(email: String) {
        self.email = email
    }
}

// MARK: - AuthService

/// Owns the credential-exchange endpoints and the token's lifetime.
///
/// Decision 0001 makes the Bearer token the primary transport for nearly
/// the entire feature surface. `AuthService` is the single place that
/// fetches it, persists it via `TokenStore`, and clears it on sign-out.
///
/// The interactive cookie-session login for the small session-only
/// allowlist is a separate concern; it lives behind `SessionEstablisher`
/// (in `AuthTransport.swift`) so feature code never calls it directly.
public protocol AuthServiceProtocol: Sendable {
    /// Exchanges credentials for a Bearer token, persists it in the
    /// `TokenStore`, and returns the token.
    @discardableResult
    func signIn(email: String, password: String) async throws -> String

    /// Registers a new account. The API also returns a token on success,
    /// which is persisted just like `signIn`.
    @discardableResult
    func register(email: String, password: String, username: String?) async throws -> String

    /// Triggers the password-reset email flow. Does not require a token.
    func requestPasswordReset(email: String) async throws

    /// Clears the persisted token. Domain code should also clear caches.
    func signOut() async throws

    /// Whether a token is currently stored. Cheap — used by the UI to pick
    /// between onboarding and the main window at launch.
    func hasStoredToken() async throws -> Bool
}

public final class AuthService: AuthServiceProtocol {

    private let api: APIClientProtocol
    private let tokenStore: TokenStore

    public init(api: APIClientProtocol, tokenStore: TokenStore) {
        self.api = api
        self.tokenStore = tokenStore
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> String {
        let request = Request<SyncTokenResponse>(
            method: .post,
            path: "/api/auth/sync-token",
            body: .json(CredentialsRequest(email: email, password: password)),
            auth: .none
        )
        let response = try await api.send(request)
        try tokenStore.write(response.token)
        return response.token
    }

    @discardableResult
    public func register(
        email: String,
        password: String,
        username: String?
    ) async throws -> String {
        let request = Request<SyncTokenResponse>(
            method: .post,
            path: "/api/auth/register",
            body: .json(RegisterRequest(email: email, password: password, username: username)),
            auth: .none
        )
        let response = try await api.send(request)
        try tokenStore.write(response.token)
        return response.token
    }

    public func requestPasswordReset(email: String) async throws {
        let request = Request<EmptyResponse>(
            method: .post,
            path: "/api/auth/password-reset/request",
            body: .json(PasswordResetRequest(email: email)),
            auth: .none
        )
        try await api.sendVoid(request)
    }

    public func signOut() async throws {
        try tokenStore.delete()
    }

    public func hasStoredToken() async throws -> Bool {
        try tokenStore.read() != nil
    }
}

/// A decodable placeholder for endpoints that return no meaningful body.
/// Used with `sendVoid` so the generic still resolves.
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}

    public init(from decoder: Decoder) throws {
        // Accept anything (or nothing).
    }
}
