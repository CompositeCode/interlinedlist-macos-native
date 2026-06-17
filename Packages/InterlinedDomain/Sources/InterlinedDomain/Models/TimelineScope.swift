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

    /// The `onlyMine` query flag this scope maps to. `nil` means "do not send
    /// the parameter", which the API treats as the full timeline.
    public var onlyMine: Bool? {
        switch self {
        case .all: return nil
        case .mine: return true
        }
    }
}
