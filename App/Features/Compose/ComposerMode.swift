// ComposerMode
//
// Discriminator that tells the composer window which write surface to
// invoke when "Publish" is hit (PLAN.md §6 M2 — composer drives
// `create` for new messages and `update` for edits; replies and reposts
// go through the inline reply UI and the repost sheet respectively,
// not this window).
//
// The composer window itself supports `.newPost` and `.edit`. The
// other shapes are kept here for completeness so a future iteration
// (where reply / repost is composed in the standalone window instead
// of inline) can reuse the same view model without recomputing the
// dispatch logic.

import Foundation
import InterlinedDomain

/// What the composer is being used for. Determines the navigation
/// title, the publish-button label, and which `MessagesServicing`
/// method runs on submit.
enum ComposerMode: Equatable, Sendable {

    /// Compose a brand-new top-level message.
    case newPost

    /// Edit an existing message. Carries the id so `update` can target
    /// it; the body / tags / visibility are pre-populated on the view
    /// model from the original message.
    case edit(messageID: String, original: Message)

    /// Human-friendly title shown in the window's nav bar.
    var windowTitle: String {
        switch self {
        case .newPost: return "New Message"
        case .edit: return "Edit Message"
        }
    }

    /// Label for the primary action.
    var publishButtonLabel: String {
        switch self {
        case .newPost: return "Publish"
        case .edit: return "Save Changes"
        }
    }
}
