// OnboardingViewModel
//
// Drives the sign-in / register / forgot-password surface (M7
// Onboarding window). The view is a thin shell over this class:
// it observes state, dispatches user intents, and leaves all
// validation and service-call logic here so unit tests cover the
// behaviour without touching SwiftUI.
//
// All three auth flows share a single `submit()` entry point that
// branches on `mode`. Input is validated before the service is
// called — an invalid state sets `errorMessage` and returns early
// without issuing a network request.
//
// Per Decision 0003 this file consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

// MARK: - OnboardingMode

/// The three surfaces the onboarding window can show.
enum OnboardingMode: Equatable {
    case signIn
    case register
    case forgotPassword
}

// MARK: - OnboardingViewModel

@MainActor
@Observable
final class OnboardingViewModel {

    // MARK: - Injected

    private let session: SessionManaging

    // MARK: - Form state

    var email: String = ""
    var password: String = ""
    var username: String = ""
    var confirmPassword: String = ""
    var mode: OnboardingMode = .signIn

    // MARK: - UI feedback

    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var didSendReset: Bool = false

    // MARK: - Init

    init(session: SessionManaging) {
        self.session = session
    }

    // MARK: - Intents

    /// Switches the form to a new mode, clearing transient error state and
    /// resetting the credential fields so stale input does not carry over.
    func switchMode(to newMode: OnboardingMode) {
        mode = newMode
        errorMessage = nil
        password = ""
        confirmPassword = ""
    }

    /// Validates the current form state and, if valid, calls the
    /// appropriate `SessionManaging` method. Sets `isLoading` for the
    /// duration of the async call; on failure sets `errorMessage`.
    func submit() async {
        errorMessage = nil

        switch mode {
        case .signIn:
            await submitSignIn()
        case .register:
            await submitRegister()
        case .forgotPassword:
            await submitForgotPassword()
        }
    }

    // MARK: - Private submit helpers

    private func submitSignIn() async {
        guard validate(email: email) else { return }
        guard !password.isEmpty else {
            errorMessage = "Password is required."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await session.signIn(email: email, password: password)
            errorMessage = nil
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func submitRegister() async {
        guard validate(email: email) else { return }
        guard !password.isEmpty else {
            errorMessage = "Password is required."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let usernameOpt: String? = username.trimmingCharacters(in: .whitespaces).isEmpty ? nil : username
        do {
            _ = try await session.register(email: email, password: password, username: usernameOpt)
            errorMessage = nil
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func submitForgotPassword() async {
        guard validate(email: email) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await session.requestPasswordReset(email: email)
            didSendReset = true
            errorMessage = nil
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    // MARK: - Validation helpers

    /// Returns `true` when the email is non-empty and matches a minimal
    /// RFC-5322 shape; sets `errorMessage` and returns `false` otherwise.
    @discardableResult
    private func validate(email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Email address is required."
            return false
        }
        // Minimal validity: at-sign present and something on both sides.
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            errorMessage = "Please enter a valid email address."
            return false
        }
        return true
    }

    // MARK: - Error formatting

    /// Maps any thrown error to a user-facing string. Generic fallback
    /// avoids leaking internal error codes into the UI.
    private func humanReadable(_ error: Error) -> String {
        // Surface the localised description for well-known domain errors;
        // generic catch-all for unexpected types.
        let description = error.localizedDescription
        if description.isEmpty {
            return "Something went wrong. Please try again."
        }
        return description
    }
}
