import Foundation
import InterlinedKit

/// Deterministic `AuthServiceProtocol` stub for `SessionService` tests.
///
/// Tracks a simulated stored-token flag and records which lifecycle calls were
/// made, so tests can assert sign-out clears the token and request-reset is
/// forwarded. Any method can be primed to throw.
actor StubAuthService: AuthServiceProtocol {

    var storedToken: Bool
    private(set) var signedInCount = 0
    private(set) var registeredCount = 0
    private(set) var requestedResetCount = 0
    private(set) var signedOutCount = 0
    private(set) var lastResetEmail: String?

    private var errorToThrow: APIError?

    init(storedToken: Bool = false) {
        self.storedToken = storedToken
    }

    func setStoredToken(_ value: Bool) {
        storedToken = value
    }

    func primeError(_ error: APIError?) {
        errorToThrow = error
    }

    // MARK: AuthServiceProtocol

    @discardableResult
    func signIn(email: String, password: String) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        signedInCount += 1
        storedToken = true
        return "il_tok_stub"
    }

    @discardableResult
    func register(email: String, password: String, username: String?) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        registeredCount += 1
        storedToken = true
        return "il_tok_stub"
    }

    func requestPasswordReset(email: String) async throws {
        if let errorToThrow { throw errorToThrow }
        requestedResetCount += 1
        lastResetEmail = email
    }

    func resetPassword(token: String, newPassword: String) async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func sendVerificationEmail(email: String) async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func verifyEmail(token: String) async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func logout() async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func signOut() async throws {
        signedOutCount += 1
        storedToken = false
    }

    func hasStoredToken() async throws -> Bool {
        if let errorToThrow { throw errorToThrow }
        return storedToken
    }
}
