// PreferencesViewModel
//
// Drives the Settings ▸ Preferences pane — the account's server-synced
// preferences (work-consolidation.md — settings storage). Reads through
// `UserServicing` only, so a stub service drives tests without networking.
//
// Loads the current settings on appear, binds them to the pane's controls
// (a mutable `settings` working copy), and persists on Save via
// `POST /api/user/update`. `hasChanges` gates the Save button so an
// unchanged pane never round-trips.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class PreferencesViewModel {

    private let userService: UserServicing

    /// The working copy bound directly to the pane's controls. `save()`
    /// persists it; a successful load/save resets `lastSaved` to match.
    var settings: UserSettings = .default

    /// The last value confirmed by the server, used to detect unsaved edits.
    private(set) var lastSaved: UserSettings = .default

    /// True while the initial load is in flight.
    private(set) var isLoading: Bool = false

    /// True while a save round-trip is in flight.
    private(set) var isSaving: Bool = false

    /// Surfaced error from the most recent failed load or save. Cleared at the
    /// start of the next attempt.
    private(set) var error: Error?

    /// Whether the working copy differs from what the server last confirmed.
    /// Drives the Save button's enabled state.
    var hasChanges: Bool { settings != lastSaved }

    init(userService: UserServicing) {
        self.userService = userService
    }

    /// Loads the current settings from the server. On failure surfaces the
    /// error and leaves the working copy at its last value (`.default` on the
    /// first load), so the pane still renders usable controls.
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let loaded = try await userService.settings()
            settings = loaded
            lastSaved = loaded
        } catch {
            self.error = error
        }
    }

    /// Persists the working copy. No-op when there are no changes or a save is
    /// already in flight. On success replaces the working copy with the
    /// server's authoritative post-update settings.
    func save() async {
        guard hasChanges, !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let updated = try await userService.updateSettings(settings)
            settings = updated
            lastSaved = updated
        } catch {
            self.error = error
        }
    }
}
