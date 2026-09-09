import Foundation

/// Which slice of the timeline feed to load (PLAN.md §1).
///
/// The tag filter is intentionally *not* part of this enum — it is an
/// independent optional parameter on the service call, because any scope can
/// be combined with a tag. `MessagesService` maps `.mine` to the API's
/// `onlyMine=true` query flag; `.all` leaves it unset.
public enum TimelineScope: Sendable, Equatable, Hashable, CaseIterable {
    /// Everyone's public timeline (`onlyMine` unset).
    case all
    /// Only the signed-in user's own messages (`onlyMine=true`).
    case mine
    /// Feed of accounts the signed-in user follows. No API endpoint exists
    /// yet — `MessagesService` short-circuits and returns an empty page
    /// so the UI can show a "coming soon" empty state (App Store Guideline
    /// 2.1 requires every visible control to have a graceful unavailable
    /// state rather than a broken or missing one).
    case following
    /// Feed of accounts that follow the signed-in user — the destination for
    /// the account's `followers_only` viewing preference (G35 / issue #43).
    ///
    /// Like `.following`, it has no API endpoint. VERIFIED live 2026-09-09:
    /// `GET /api/messages` honours only `onlyMine`; `?scope=following`,
    /// `?viewingPreference=followers_only` and `?filter=followers_only` each
    /// return the identical unfiltered page. The case exists so a web-set
    /// `followers_only` preference lands on an honest "coming soon" state
    /// instead of being silently rewritten to the full timeline.
    case followers

    /// The `onlyMine` query flag this scope maps to. `nil` means "do not send
    /// the parameter", which the API treats as the full timeline.
    /// `.following` / `.followers` are short-circuited in the service before
    /// this property is ever consulted — the values here are kept as `nil`
    /// for safety.
    public var onlyMine: Bool? {
        switch self {
        case .all:       return nil
        case .mine:      return true
        case .following: return nil
        case .followers: return nil
        }
    }

    /// Whether the API can serve this scope today. `false` means the UI must
    /// render the "coming soon" empty state rather than an empty feed that
    /// looks like "you have no messages".
    public var hasBackendFeed: Bool {
        switch self {
        case .all, .mine:            return true
        case .following, .followers: return false
        }
    }
}
