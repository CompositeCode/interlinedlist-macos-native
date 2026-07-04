// StubSessionManaging
//
// Test double for `SessionManaging` used by `CurrentUserStoreTests`
// and `OnboardingViewModelTests`. Holds a queued state stream and
// pre-staged outcomes for all `SessionManaging` methods.
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
    private var signInOutcome: Result<CurrentUser, Error>?
    private var registerOutcome: Result<CurrentUser, Error>?
    private var passwordResetOutcome: Result<Void, Error>?
    private var signOutOutcome: Result<Void, Error>?

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

    func enqueueSignIn(success user: CurrentUser) {
        signInOutcome = .success(user)
    }

    func enqueueSignIn(failure error: Error) {
        signInOutcome = .failure(error)
    }

    func enqueueRegister(success user: CurrentUser) {
        registerOutcome = .success(user)
    }

    func enqueueRegister(failure error: Error) {
        registerOutcome = .failure(error)
    }

    func enqueuePasswordReset(success: Void = ()) {
        passwordResetOutcome = .success(())
    }

    func enqueuePasswordReset(failure error: Error) {
        passwordResetOutcome = .failure(error)
    }

    func enqueueSignOut(failure error: Error) {
        signOutOutcome = .failure(error)
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
        guard let outcome = signInOutcome else {
            throw TestError.upstream("signIn not staged in stub")
        }
        switch outcome {
        case .success(let user):
            let state = SessionState.signedIn(user)
            currentSessionState = state
            continuation.yield(state)
            return user
        case .failure(let error):
            throw error
        }
    }

    @discardableResult
    func register(email: String, password: String, username: String?) async throws -> CurrentUser {
        guard let outcome = registerOutcome else {
            throw TestError.upstream("register not staged in stub")
        }
        switch outcome {
        case .success(let user):
            let state = SessionState.signedIn(user)
            currentSessionState = state
            continuation.yield(state)
            return user
        case .failure(let error):
            throw error
        }
    }

    func requestPasswordReset(email: String) async throws {
        guard let outcome = passwordResetOutcome else {
            throw TestError.upstream("requestPasswordReset not staged in stub")
        }
        switch outcome {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func signOut() async throws {
        if let outcome = signOutOutcome {
            switch outcome {
            case .success:
                break
            case .failure(let error):
                throw error
            }
        }
        currentSessionState = .signedOut
        continuation.yield(.signedOut)
    }
}
