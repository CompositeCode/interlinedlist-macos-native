// RepostSheetViewModel
//
// Drives the small repost sheet opened from the message row context
// menu (PLAN.md §6 M2 — "Repost action"). The sheet collects an
// optional commentary string and a visibility, then calls
// `MessagesServicing.repost(_:commentary:visibility:)`. On success
// posts `.messageReposted` so the open Timeline view prepends the
// repost.
//
// Tiny on purpose: no validation other than what the kit accepts
// (bare reposts with no commentary are a valid wire shape). Kept
// separate from `ComposerViewModel` so the repost flow doesn't drag
// in the full composer's mode-dispatch logic.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class RepostSheetViewModel {

    // MARK: - Inputs

    private let messages: MessagesServicing
    private let eventBus: ComposerEventBus

    /// The id of the message being reposted. Sent on the wire as
    /// `pushedMessageId`.
    let originalMessageID: String

    // MARK: - Editable state

    /// Optional commentary the user attaches above the repost. Empty
    /// string and `nil` both encode as an empty body per the kit's
    /// `repost` convenience.
    var commentary: String = ""

    /// Visibility of the *repost*, not the original. Defaults to
    /// public — a bare-repost is implicitly a share.
    var visibility: Visibility = .public

    // MARK: - Read-only state

    /// True while the round-trip is in flight.
    private(set) var isSubmitting: Bool = false

    /// The last submission error. Cleared on the next submit.
    private(set) var error: Error?

    /// Flips true on success; the sheet observes it to dismiss.
    private(set) var didFinish: Bool = false

    init(
        messages: MessagesServicing,
        eventBus: ComposerEventBus,
        originalMessageID: String
    ) {
        self.messages = messages
        self.eventBus = eventBus
        self.originalMessageID = originalMessageID
    }

    /// Submits the repost. `nil` commentary when the field is empty so
    /// the kit knows to send an empty body without ceremony.
    func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        let trimmed = commentary.trimmingCharacters(in: .whitespacesAndNewlines)
        let commentaryOrNil: String? = trimmed.isEmpty ? nil : trimmed

        do {
            let reposted = try await messages.repost(
                originalMessageID,
                commentary: commentaryOrNil,
                visibility: visibility
            )
            eventBus.post(.messageReposted(reposted))
            didFinish = true
        } catch {
            self.error = error
        }
    }
}
