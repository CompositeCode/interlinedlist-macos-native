// UnreadBadgeAggregator
//
// Single owner of the macOS dock-tile badge label (the-gaps.md G1).
//
// Before Direct Messages, the dock badge was written directly by
// `NotificationsUnreadBadgeCoordinator` from the notifications-unread
// count. DMs add a *second* independent unread source, and the dock has
// exactly one badge, so the two counts must be summed by a single writer
// — otherwise whichever coordinator wrote last would clobber the other's
// contribution.
//
// This aggregator holds the latest count from each named source and, on
// every update, writes the sum through the injected dock-badge closure
// (the one `@MainActor` AppKit reach, provided by the composition root
// so tests record without AppKit). Both the notifications coordinator and
// the DM badge coordinator now report *into* the aggregator instead of
// writing the badge themselves.
//
// Deviation note (reported to the user): this changes how the dock badge
// aggregates. Notifications no longer own the badge label outright — they
// own the `.notifications` slot of a summed total. The notifications count
// alone is unchanged; the badge simply also reflects DM unread now.
//
// Decision 0003 compliance: lives in `App/Composition/` (allowed to cross
// layers) and imports only `Foundation`. The AppKit dependency is hidden
// behind a `@MainActor` closure.

import Foundation

/// Sums per-source unread counts and writes the total to the dock badge.
/// Thread-confined to the main actor because the underlying
/// `NSApp.dockTile` write requires it and the source counts are small.
@MainActor
final class UnreadBadgeAggregator {

    /// The named unread sources contributing to the single dock badge.
    enum Source: String, Sendable, CaseIterable {
        case notifications
        case directMessages
    }

    /// The dock-badge writer, injected so tests record without AppKit.
    private let writeBadge: @MainActor @Sendable (Int) -> Void

    /// Latest count per source. Absent sources contribute zero.
    private var counts: [Source: Int] = [:]

    init(writeBadge: @escaping @MainActor @Sendable (Int) -> Void) {
        self.writeBadge = writeBadge
    }

    /// Records `count` for `source` and writes the new summed total to
    /// the badge. Negative inputs are clamped to zero defensively.
    func update(source: Source, count: Int) {
        counts[source] = max(0, count)
        writeBadge(total)
    }

    /// The current summed unread total across all sources. Exposed for
    /// tests and for a sidebar aggregate pip.
    var total: Int {
        counts.values.reduce(0, +)
    }
}
