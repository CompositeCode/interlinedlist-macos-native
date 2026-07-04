// AccountViewModel
//
// Drives the Settings > "Account" pane (PLAN.md §5 — M7 account
// management: email change, avatar upload, account deletion).
//
// Reads through `UserServicing` and `SessionManaging` only — no direct
// API access — so unit tests substitute stubs. `@Observable` so SwiftUI
// re-renders on every state change.
//
// Per decision 0003 the view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class AccountViewModel {

    // MARK: - Dependencies

    private let userService: UserServicing
    private let session: SessionManaging
    private let currentUserStore: CurrentUserStore

    // MARK: - Observable state

    /// The signed-in account, sourced live from the store so any
    /// `currentUserStore.restore()` call updates this automatically.
    var currentUser: CurrentUser? { currentUserStore.currentUser }

    /// The new email address the user is typing before confirming.
    var newEmail: String = ""

    /// Controls the file importer sheet for avatar picking.
    var avatarPickerVisible: Bool = false

    /// True while an avatar upload is in flight.
    private(set) var isLoadingAvatar: Bool = false

    /// True while an email-change request is in flight.
    private(set) var isLoadingEmailChange: Bool = false

    /// True while an account-deletion request is in flight.
    private(set) var isDeletingAccount: Bool = false

    /// The password entered in the delete-confirmation alert.
    var confirmDeletePassword: String = ""

    /// Controls the delete-confirmation alert.
    var showDeleteConfirm: Bool = false

    /// `true` after a successful `requestEmailChange` call. The view
    /// shows a success banner while this is `true`.
    private(set) var emailChangeSuccess: Bool = false

    /// Surfaced error from the most recent failed mutation. Cleared at
    /// the start of each new operation.
    private(set) var errorMessage: String?

    // MARK: - Init

    init(
        userService: UserServicing,
        session: SessionManaging,
        currentUserStore: CurrentUserStore
    ) {
        self.userService = userService
        self.session = session
        self.currentUserStore = currentUserStore
    }

    // MARK: - Intents

    /// Validates `newEmail` and, when valid, starts the server-side
    /// email-change flow. The server emails a confirmation link to the
    /// new address — no local email state changes until the user clicks
    /// the link and the next `currentUserStore.restore()` call.
    ///
    /// Validation order:
    /// 1. Non-empty after whitespace trimming.
    /// 2. Different from the current email (no-op change rejected early).
    /// 3. Contains an `@` and a `.` in the domain part (format guard).
    func requestEmailChange() async {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        emailChangeSuccess = false
        errorMessage = nil

        guard !trimmed.isEmpty else {
            errorMessage = "Email address cannot be empty."
            return
        }

        if let current = currentUser?.email, trimmed == current {
            errorMessage = "New email must be different from your current email."
            return
        }

        guard isValidEmailFormat(trimmed) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        isLoadingEmailChange = true
        defer { isLoadingEmailChange = false }

        do {
            try await userService.requestEmailChange(newEmail: trimmed)
            emailChangeSuccess = true
            newEmail = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Uploads the supplied image bytes as the signed-in user's avatar.
    /// On success, calls `currentUserStore.restore()` so the new avatar
    /// URL flows through to any view reading `currentUser.avatarURL`.
    func pickAndUploadAvatar(data: Data, contentType: String) async {
        isLoadingAvatar = true
        defer { isLoadingAvatar = false }
        errorMessage = nil

        do {
            _ = try await userService.uploadAvatar(imageData: data, contentType: contentType)
            _ = try? await currentUserStore.restore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Signs the current user out immediately. Clears the session,
    /// which causes `AppRootView` to switch to `OnboardingView`.
    func signOut() async {
        errorMessage = nil
        do {
            try await session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Permanently deletes the account using `confirmDeletePassword`.
    /// On success, calls `session.signOut()`. The calling view should
    /// navigate away from the Settings window when the session ends.
    func deleteAccount() async {
        isDeletingAccount = true
        defer {
            isDeletingAccount = false
            confirmDeletePassword = ""
        }
        errorMessage = nil

        do {
            try await userService.deleteAccount(password: confirmDeletePassword)
            try? await session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func isValidEmailFormat(_ email: String) -> Bool {
        guard let atIndex = email.firstIndex(of: "@") else { return false }
        let domain = email[email.index(after: atIndex)...]
        return domain.contains(".")
    }
}
