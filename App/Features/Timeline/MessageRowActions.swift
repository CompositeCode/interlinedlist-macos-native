// MessageRowActions
//
// The set of optional callbacks a host wires into `MessageRowView`
// (GitHub #27). Collected into one value rather than passed as a long tail
// of individual closure parameters — the row had grown to eight, and the
// web-parity actions (Reply / Link / Push / Push & Comment) would have taken
// it past readable.
//
// The contract the row already had is preserved exactly:
//
//   - Every handler is optional. A `nil` handler means the row does not
//     render that affordance at all, so preview and static contexts stay
//     clean and the user never sees an enabled-but-broken control.
//   - The row stays passive: it reports intent, the host performs the work
//     (network call, sheet presentation, confirmation dialog).
//
// Three hosts build one of these: the timeline list, the message-detail
// header and reply rows, and the search results list.

import Foundation
import InterlinedDomain

struct MessageRowActions {

    /// Toggle the "I Dig!" reaction. When nil the dig glyph renders as
    /// plain text instead of a button.
    var onToggleDig: ((Message) -> Void)?

    /// Reply to this message. The host is expected to route to the
    /// message-detail composer rather than open a second write surface.
    var onReply: ((Message) -> Void)?

    /// Bare, one-tap Push (repost with no commentary).
    var onPush: ((Message) -> Void)?

    /// Push with commentary — the host opens the Push & Comment sheet.
    var onPushAndComment: ((Message) -> Void)?

    /// Edit. Only ever invoked when the row's `canEdit` is true.
    var onEdit: ((Message) -> Void)?

    /// Delete. Only invoked when `canEdit` is true; the host owns the
    /// confirmation dialog.
    var onDelete: ((Message) -> Void)?

    /// Block the author (work-consolidation.md G2).
    var onBlock: ((Message) -> Void)?

    /// Mute the author.
    var onMute: ((Message) -> Void)?

    /// Report this message — the host opens its report sheet. Satisfies
    /// App Store Review Guideline 1.2 (user-generated content needs a
    /// report mechanism).
    var onReport: ((Message) -> Void)?

    /// Create a GitHub issue pre-filled from this message
    /// (work-consolidation.md G4).
    var onCreateGitHubIssue: ((Message) -> Void)?

    /// No handlers wired — the row renders read-only. Used by previews and
    /// by the search results list, where a hit is a navigation target
    /// rather than an action surface.
    ///
    /// Computed rather than a `static let`: the handlers are plain
    /// non-`Sendable` closures, so a shared static instance is not
    /// concurrency-safe under Swift 6. Each caller gets its own empty value.
    static var none: MessageRowActions { MessageRowActions() }
}
