import Foundation
import InterlinedKit

// MARK: - SessionState

/// Whether someone is signed in, and who. The App layer's `@Observable` view
/// model adapts this; the domain layer stays UI-agnostic (no SwiftUI here).
public enum SessionState: Sendable, Equatable {
    case signedOut
    case signedIn(CurrentUser)

    /// The signed-in account, or `nil` when signed out.
    public var currentUser: CurrentUser? {
        switch self {
        case .signedOut: return nil
        case .signedIn(let user): return user
        }
    }

    public var isSignedIn: Bool {
        currentUser != nil
    }
}

// MARK: - SessionManaging

/// The authentication + current-account surface the App layer codes against.
///
/// Combines the kit's `AuthServiceProtocol` (credential exchange + token
/// lifetime) with the `GET /api/user` read that turns a stored token into a
/// `CurrentUser`. Sign-out clears both the token and any injected cache.
public protocol SessionManaging: Sendable {

    /// The current session, observed as a stream. Yields the present state
    /// immediately on subscription, then every subsequent change. The App
    /// layer's view model mirrors this into `@Observable` state.
    var states: AsyncStream<SessionState> { get }

    /// The current session state, read once.
    func currentState() async -> SessionState

    /// At launch: if a token is stored, fetch `CurrentUser` and become
    /// `.signedIn`; otherwise `.signedOut`. A failed user fetch propagates so
    /// the caller can decide whether to clear a stale token.
    @discardableResult
    func restore() async throws -> SessionState

    /// Exchanges credentials for a token, fetches the account, and becomes
    /// `.signedIn`.
    @discardableResult
    func signIn(email: String, password: String) async throws -> CurrentUser

    /// Registers a new account, then signs in the same way.
    @discardableResult
    func register(email: String, password: String, username: String?) async throws -> CurrentUser

    /// Triggers the password-reset email flow. Does not change session state.
    func requestPasswordReset(email: String) async throws

    /// Clears the stored token and any injected cache, and becomes `.signedOut`.
    func signOut() async throws
}

// MARK: - SessionService

/// `actor` so the current `SessionState` and the set of stream subscribers are
/// mutated safely under Swift 6 strict concurrency.
public actor SessionService: SessionManaging {

    private let auth: AuthServiceProtocol
    private let api: APIClientProtocol
    private let cache: MessageStore?

    private var state: SessionState = .signedOut
    private var continuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]

    public init(auth: AuthServiceProtocol, api: APIClientProtocol, cache: MessageStore? = nil) {
        self.auth = auth
        self.api = api
        self.cache = cache
    }

    // MARK: Observation

    public nonisolated var states: AsyncStream<SessionState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id) }
            }
        }
    }

    private func register(_ continuation: AsyncStream<SessionState>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func unregister(_ id: UUID) {
        continuations[id] = nil
    }

    public func currentState() async -> SessionState {
        state
    }

    // MARK: Lifecycle

    @discardableResult
    public func restore() async throws -> SessionState {
        guard try await auth.hasStoredToken() else {
            return transition(to: .signedOut)
        }
        let user = try await fetchCurrentUser()
        return transition(to: .signedIn(user))
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> CurrentUser {
        try await auth.signIn(email: email, password: password)
        let user = try await fetchCurrentUser()
        _ = transition(to: .signedIn(user))
        return user
    }

    @discardableResult
    public func register(email: String, password: String, username: String?) async throws -> CurrentUser {
        try await auth.register(email: email, password: password, username: username)
        let user = try await fetchCurrentUser()
        _ = transition(to: .signedIn(user))
        return user
    }

    public func requestPasswordReset(email: String) async throws {
        try await auth.requestPasswordReset(email: email)
    }

    public func signOut() async throws {
        try await auth.signOut()
        await cache?.clear()
        _ = transition(to: .signedOut)
    }

    // MARK: - Internals

    private func fetchCurrentUser() async throws -> CurrentUser {
        let response = try await api.send(User.current())
        return CurrentUser(from: response.user)
    }

    @discardableResult
    private func transition(to newState: SessionState) -> SessionState {
        state = newState
        for continuation in continuations.values {
            continuation.yield(newState)
        }
        return newState
    }
}
