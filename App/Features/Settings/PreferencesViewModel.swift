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

    /// App-wide preferences store to write through to, so a toggle takes
    /// effect on the timeline immediately rather than at the next launch
    /// (G21). Optional so existing tests construct the view model unchanged.
    private weak var preferencesStore: UserPreferencesStore?

    /// The session-cached account projection. A successful save re-resolves it
    /// so anything reading a preference off `CurrentUser` — today the composer's
    /// default visibility — picks the change up without an app restart. Optional
    /// so existing tests and previews construct the view model unchanged.
    ///
    /// Distinct from `preferencesStore` on purpose: this one carries
    /// `CurrentUser` (composer default visibility), that one carries
    /// `UserSettings` (link previews). A save has to refresh both.
    private let currentUserStore: CurrentUserStore?

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

    init(
        userService: UserServicing,
        preferencesStore: UserPreferencesStore? = nil,
        currentUserStore: CurrentUserStore? = nil
    ) {
        self.userService = userService
        self.preferencesStore = preferencesStore
        self.currentUserStore = currentUserStore
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
            preferencesStore?.adopt(loaded)
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
            // Two independent caches read preferences, so a save refreshes
            // both: `UserSettings` for the timeline's link-preview gate (G21)
            // and `CurrentUser` for the composer's default visibility (#34).
            preferencesStore?.adopt(updated)
            // The error is swallowed because the save itself succeeded and a
            // failed re-read must not be reported as a failed save. Mirrors
            // `AccountViewModel`'s post-mutation refresh.
            _ = try? await currentUserStore?.restore()
        } catch {
            self.error = error
        }
    }
}
