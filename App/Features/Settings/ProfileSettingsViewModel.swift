// ProfileSettingsViewModel
//
// Drives Settings ▸ Profile (GitHub #46 / G34) — the identity half of the
// account: display name, bio, avatar, theme and the per-message character cap.
//
// Until this pane existed **you could not edit your own display name or bio from
// the macOS app at all**, even though `UpdateUserRequest` had carried
// `displayName`, `bio` and `theme` since it was written and nothing called them.
//
// Reuses `PreferencesViewModel`'s idiom deliberately rather than inventing a
// second save shape: a working copy bound to the controls, a `lastSaved`
// snapshot, `hasChanges` gating Save, and a change-gated PATCH so an untouched
// field is never written.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ProfileSettingsViewModel {

    private let userService: UserServicing

    /// The platform-limits seam. Optional because the pane is fully usable
    /// without it — `ContentLimits.default` already carries the live ceiling.
    private let contentLimits: ContentLimitsProviding?

    /// The session-cached account projection, re-resolved after a save so
    /// anything reading the display name or avatar off `CurrentUser` picks the
    /// change up without a relaunch. Optional so tests construct this unchanged.
    private let currentUserStore: CurrentUserStore?

    // MARK: - Observable state

    /// The working copy bound to the pane's controls.
    var settings: ProfileSettings = ProfileSettings()

    /// The last value the server confirmed, for change detection.
    private(set) var lastSaved: ProfileSettings = ProfileSettings()

    /// The platform limits, so the message-cap stepper can say which number is
    /// the account's and which is the platform's.
    private(set) var limits: ContentLimits = .default

    /// The URL typed into the "set avatar from a URL" field.
    var avatarURLInput: String = ""

    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var isUpdatingAvatar: Bool = false

    /// Surfaced error from the most recent failed load, save or avatar write.
    private(set) var error: Error?

    /// A transient confirmation — "Saved", "Avatar updated", "Reset email sent".
    /// Cleared at the start of the next attempt.
    private(set) var confirmation: String?

    var hasChanges: Bool { settings.hasChanges(from: lastSaved) }

    /// The theme rows the picker offers: the three documented values, plus the
    /// account's own when the server holds a token this build does not know.
    ///
    /// The second half is not hypothetical here. `theme` is **unvalidated**
    /// server-side — probed 2026-09-15, `PATCH /api/user/update` stored
    /// `"nonsense"` without complaint — so an unrecognised value is a thing that
    /// can genuinely be on an account. Without offering it, the `Picker` would
    /// have a selection matching no tag (SwiftUI renders that as a blank
    /// control) and the first edit to any other field would silently rewrite it.
    var themeOptions: [AppTheme] {
        let selectable = AppTheme.selectable
        guard !selectable.contains(settings.theme) else { return selectable }
        return selectable + [settings.theme]
    }

    /// The character budget the composer actually enforces — the lower of the
    /// platform ceiling and the account's cap. Shown in the pane so the two
    /// numbers are legible rather than mysterious.
    var effectiveMessageLength: Int {
        limits.effectiveMessageLength(accountCap: settings.maxMessageLength)
    }

    /// True when the account's cap is above the platform ceiling, so the pane
    /// can say which one is really in force instead of showing a number the
    /// composer will not honour.
    var accountCapExceedsPlatform: Bool {
        settings.maxMessageLength > limits.messageMaxContentLength
    }

    // MARK: - Init

    init(
        userService: UserServicing,
        contentLimits: ContentLimitsProviding? = nil,
        currentUserStore: CurrentUserStore? = nil
    ) {
        self.userService = userService
        self.contentLimits = contentLimits
        self.currentUserStore = currentUserStore
    }

    // MARK: - Intents

    func load() async {
        isLoading = true
        error = nil
        confirmation = nil
        defer { isLoading = false }
        do {
            let loaded = try await userService.profileSettings()
            settings = loaded
            lastSaved = loaded
        } catch {
            self.error = error
        }
        // The platform limits are a separate, soft read: the pane is fully
        // usable without them, and failing the whole load because the ceiling
        // could not be fetched would be a poor trade. The provider never throws
        // — it falls back to `ContentLimits.default`.
        if let contentLimits {
            limits = await contentLimits.limits()
        }
    }

    func save() async {
        guard hasChanges, !isSaving else { return }
        isSaving = true
        error = nil
        confirmation = nil
        defer { isSaving = false }
        do {
            let saved = try await userService.updateProfileSettings(settings, changedFrom: lastSaved)
            settings = saved
            lastSaved = saved
            confirmation = "Saved."
            await refreshSession()
        } catch {
            // The working copy is deliberately left alone: the user's typing is
            // the one thing a failed save must not throw away.
            self.error = error
        }
    }

    /// Discards unsaved edits. The pane's "Revert" affordance.
    func revert() {
        settings = lastSaved
        error = nil
        confirmation = nil
    }

    func setAvatarFromURL() async {
        let input = avatarURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isUpdatingAvatar else { return }
        isUpdatingAvatar = true
        error = nil
        confirmation = nil
        defer { isUpdatingAvatar = false }
        do {
            let url = try await userService.setAvatarFromURL(input)
            // The avatar lives outside the change-gated body — it is written by
            // its own route — so the working copy and the saved snapshot are
            // both updated, or Save would think the avatar was an unsaved edit.
            settings.avatarURL = url ?? settings.avatarURL
            lastSaved.avatarURL = settings.avatarURL
            avatarURLInput = ""
            confirmation = "Avatar updated."
            await refreshSession()
        } catch {
            self.error = error
        }
    }

    func uploadAvatar(imageData: Data, contentType: String) async {
        guard !isUpdatingAvatar else { return }
        isUpdatingAvatar = true
        error = nil
        confirmation = nil
        defer { isUpdatingAvatar = false }
        do {
            let url = try await userService.uploadAvatar(imageData: imageData, contentType: contentType)
            settings.avatarURL = url ?? settings.avatarURL
            lastSaved.avatarURL = settings.avatarURL
            confirmation = "Avatar updated."
            await refreshSession()
        } catch {
            self.error = error
        }
    }

    /// Sends the password-reset email.
    ///
    /// Reset-by-email, **not** change-in-place: there is no change-password
    /// route on this API (probed 2026-09-15 — only `forgot-password`,
    /// `reset-password`, and an admin-only one). The pane says so rather than
    /// shipping a form pointed at a route that does not exist.
    func requestPasswordReset() async {
        guard let email = currentUserStore?.currentUser?.email, !email.isEmpty else {
            error = ProfileSettingsUIError.noEmailOnAccount
            return
        }
        error = nil
        confirmation = nil
        do {
            try await userService.requestPasswordReset(email: email)
            confirmation = "Password reset email sent to \(email)."
        } catch {
            self.error = error
        }
    }
}

/// Failures this pane can report that are about the pane, not the API.
enum ProfileSettingsUIError: Error, LocalizedError, Equatable {
    case noEmailOnAccount

    var errorDescription: String? {
        switch self {
        case .noEmailOnAccount:
            return "We don't have an email address for this account to send a reset link to."
        }
    }
}

extension ProfileSettingsViewModel {

    /// Re-resolves the session-cached account so the sidebar avatar, the
    /// composer's character budget and anything else reading `CurrentUser` pick
    /// a save up without a relaunch.
    ///
    /// Soft on purpose: the save already succeeded, and failing to refresh a
    /// cache is not a reason to tell the user their edit did not land.
    fileprivate func refreshSession() async {
        _ = try? await currentUserStore?.restore()
    }
}
