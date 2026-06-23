// StubSessionManaging
//
// Test double for `SessionManaging` used by `CurrentUserStoreTests`.
// Holds a queued state stream and a pre-staged `restore` outcome.
// `states` is `nonisolated` to match the production protocol; the
// underlying stream is constructed on init and yields whatever
// `enqueue(state:)` pushes into it.

import Foundation
import InterlinedDomain

actor StubSessionManaging: SessionManaging {

    private let continuation: AsyncStream<SessionState>.Continuation
    private let stream: AsyncStream<SessionState>
    private var currentSessionState: SessionState = .signedOut
    private var restoreOutcome: Result<SessionState, Error>?

    init() {
        var continuationRef: AsyncStream<SessionState>.Continuation!
        self.stream = AsyncStream { continuationRef = $0 }
        self.continuation = continuationRef
    }

    // MARK: Test programming

    func enqueueState(_ state: SessionState) {
        currentSessionState = state
        continuation.yield(state)
    }

    func enqueueRestore(success state: SessionState) {
        restoreOutcome = .success(state)
    }

    func enqueueRestore(failure error: Error) {
        restoreOutcome = .failure(error)
    }

    // MARK: SessionManaging

    nonisolated var states: AsyncStream<SessionState> { stream }

    func currentState() async -> SessionState { currentSessionState }

    @discardableResult
    func restore() async throws -> SessionState {
        guard let restoreOutcome else { return currentSessionState }
        switch restoreOutcome {
        case .success(let state):
            currentSessionState = state
            continuation.yield(state)
            return state
        case .failure(let error):
            throw error
        }
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> CurrentUser {
        throw TestError.upstream("signIn not implemented for stub")
    }

    @discardableResult
    func register(email: String, password: String, username: String?) async throws -> CurrentUser {
        throw TestError.upstream("register not implemented for stub")
    }

    func requestPasswordReset(email: String) async throws {
        throw TestError.upstream("requestPasswordReset not implemented for stub")
    }

    func signOut() async throws {
        currentSessionState = .signedOut
        continuation.yield(.signedOut)
    }
}
