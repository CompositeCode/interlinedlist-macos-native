// UserPreferencesStore
//
// App-layer, app-wide projection of the account's server-synced reading
// preferences (`UserSettings`), so views outside Settings can honour them.
//
// Why this exists (work-consolidation.md G21): Settings ▸ Preferences shipped
// a "Show link previews" toggle that was persisted to the server and read back
// by `PreferencesViewModel` — and by nothing else. `MessageRowView` rendered
// previews unconditionally, so turning the toggle off changed nothing. The
// preference had no app-wide reader because there was no app-wide holder.
//
// Mirrors `CurrentUserStore`: `@MainActor @Observable`, constructed in
// `AppEnvironment`, read synchronously by views. Loading never blocks — a
// failed or in-flight load leaves the published defaults in place, so the
// timeline renders normally rather than waiting on a preferences round-trip.
//
// Per Decision 0003 this file consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class UserPreferencesStore {

    private let userService: UserServicing

    /// The account's reading/posting preferences. Starts at `.default` (link
    /// previews on) so first paint matches the server's own default and does
    /// not flicker when the real values arrive.
    private(set) var settings: UserSettings = .default

    /// Whether rich link-preview cards should render on message rows. Bound to
    /// Settings ▸ Preferences ▸ Reading ▸ "Show link previews".
    var showLinkPreviews: Bool { settings.showPreviews }

    /// The feed slice the account asked for, mapped to the timeline's own scope
    /// vocabulary. Seeds a newly-opened timeline window so an account whose
    /// viewing preference was set on the web sees that filter honoured on
    /// launch (G35 / issue #43 acceptance criterion).
    var defaultTimelineScope: TimelineScope { settings.viewingPreference.defaultScope }

    /// How many rows the notification bell tray renders (10...40, default 20).
    var notificationTrayLimit: Int { settings.notificationTrayLimit }

    /// Whether the composer opens with its advanced post options (media /
    /// schedule / cross-post) already revealed — the web's "gear" preference.
    var showAdvancedPostSettings: Bool { settings.showAdvancedPostSettings }

    init(userService: UserServicing) {
        self.userService = userService
    }

    /// Refreshes the cached preferences from the server.
    ///
    /// Deliberately swallows failures: preferences are a display nicety, and a
    /// timeline that renders with default preferences is strictly better than
    /// one that surfaces an error banner because a secondary fetch failed. The
    /// Settings pane still reports load errors on its own.
    func refresh() async {
        guard let loaded = try? await userService.settings() else { return }
        settings = loaded
    }

    /// Adopts settings the Preferences pane just persisted, so a toggle takes
    /// effect immediately instead of waiting for the next launch or refresh.
    func adopt(_ settings: UserSettings) {
        self.settings = settings
    }
}
