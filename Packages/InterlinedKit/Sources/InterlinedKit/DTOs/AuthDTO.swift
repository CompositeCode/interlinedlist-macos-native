import Foundation

// MARK: - ForgotPasswordRequest

/// Request body for `POST /api/auth/forgot-password`: `{ "email": "string" }`.
///
/// This is the live, working password-reset entry point. The previously-coded
/// path `/api/auth/password-reset/request` returns 404 on the live API; see the
/// task report / decision notes. `AuthService.requestPasswordReset` uses this
/// endpoint and DTO.
public struct ForgotPasswordRequest: Encodable, Sendable, Equatable {
    public let email: String

    public init(email: String) {
        self.email = email
    }
}

// MARK: - ResetPasswordRequest

/// Request body for `POST /api/auth/reset-password`:
/// `{ "token": "string", "password": "string" }`. The `token` comes from the
/// reset-link email, not from the bearer `TokenStore`.
public struct ResetPasswordRequest: Encodable, Sendable, Equatable {
    public let token: String
    public let password: String

    public init(token: String, password: String) {
        self.token = token
        self.password = password
    }
}

// MARK: - SendVerificationEmailRequest

/// Request body for `POST /api/auth/send-verification-email`:
/// `{ "email": "string" }`.
public struct SendVerificationEmailRequest: Encodable, Sendable, Equatable {
    public let email: String

    public init(email: String) {
        self.email = email
    }
}

// MARK: - VerifyEmailRequest

/// Request body for `POST /api/auth/verify-email`: `{ "token": "string" }`,
/// where the token is supplied by the verification-link email.
public struct VerifyEmailRequest: Encodable, Sendable, Equatable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

// MARK: - MessageResponse

/// Generic `{ "message": "string" }` acknowledgement returned by several
/// auth endpoints (logout, reset-password, verify-email). Decoded so callers
/// can surface the server's confirmation text if they want it.
public struct MessageResponse: Decodable, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
