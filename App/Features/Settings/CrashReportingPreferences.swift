// CrashReportingPreferences
//
// The "help development by reporting crashes" flag (GitHub issue #29, PR 1).
//
// Deliberately **not** part of `UserSettings`: that type round-trips through
// `POST /api/user/update` and is shared with the web client, whereas this is a
// native-only, machine-local preference about what this Mac may send. It also
// has to be readable when signed out, which a server-synced setting is not.
//
// `UserDefaults` is injected rather than reached for globally, mirroring
// `NotificationsPermissionCoordinator` — that is what makes the view model
// testable without touching the real defaults database.
//
// Per decision 0003, this file imports no Kit symbols.

import Foundation

/// Machine-local crash-reporting preference, backed by `UserDefaults`.
///
/// Not `Sendable`: `UserDefaults` isn't, and pretending otherwise would be a
/// false promise. It doesn't need to be — the only owner is the `@MainActor`
/// view model.
struct CrashReportingPreferences {

    /// Stable across installs so a re-launch — and an app update — sees the
    /// prior decision.
    static let enabledKey = "InterlinedList.crashReporting.enabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether this Mac may offer to file a crash report.
    ///
    /// Defaults to **off**: issue #29 frames this as an opt-in "help
    /// development" setting, and `UserDefaults.bool(forKey:)` returns `false`
    /// for an absent key, so the default falls out of the storage rather than
    /// needing a registration step that could be forgotten.
    ///
    /// Note what this flag does *not* gate: capture. The signal handler is
    /// installed unconditionally, so a user who enables the setting after a
    /// crash is not told "nothing was recorded". Only the prompt and the
    /// submission are gated.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }
}
