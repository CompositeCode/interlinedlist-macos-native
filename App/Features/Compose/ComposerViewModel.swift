// ComposerViewModel
//
// Drives the composer window for new posts and edits (PLAN.md §6 M2 —
// "Composer window"). The view is a thin shell: this owns the body
// text, the tag-input string, the visibility toggle, the `isSubmitting`
// flag, and the validation rule for empty body. On submit it calls
// `MessagesServicing.create` for `.newPost` or `.update` for `.edit`,
// then posts a `ComposerEvent` so any open Timeline / Detail screen
// can mutate its rendered list in place.
//
// Reply and repost are *not* driven by this view model — reply lives
// inline at the bottom of `MessageDetailView`, and repost goes through
// a small sheet on the row. Both have their own view models so this
// composer stays simple and focused on the "long-form" cases.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ComposerViewModel {

    // MARK: - Inputs

    private let messages: MessagesServicing
    private let eventBus: ComposerEventBus
    let mode: ComposerMode

    // MARK: - Editable state

    /// Body text of the post. Markdown source — the composer treats it
    /// as plain text for M2 (no toolbar) per PLAN.md §6 M2.
    var body: String

    /// Free-form tag input. Tags are split on commas and whitespace,
    /// `#` is stripped, and empty tokens are dropped. We hold the
    /// user's raw input string so the cursor / typing experience is
    /// not interrupted by re-normalisation while typing.
    var tagsInput: String

    /// Public or private visibility. Defaults to public for new posts;
    /// pre-populated from the original message for edits.
    var visibility: Visibility

    // MARK: - Read-only state

    /// True while a `create` / `update` round-trip is in flight.
    private(set) var isSubmitting: Bool = false

    /// The last submission error. Cleared on the next submit.
    private(set) var error: Error?

    /// Set to `true` after a successful publish; the window observes
    /// this to dismiss itself. Stored rather than fired so a test can
    /// inspect the post-success state without coupling to the
    /// dismissal mechanism.
    private(set) var didFinish: Bool = false

    // MARK: - Validation

    /// Whether the current body would be accepted for submit.
    ///
    /// Empty body is rejected by the M2 composer per the task
    /// requirements ("Validate non-empty body"). The domain layer does
    /// not pre-validate — that's deliberate so reposts can carry an
    /// empty body — but this composer is the new-post / edit surface,
    /// where an empty body is always an error.
    var isPublishable: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Init

    init(
        messages: MessagesServicing,
        eventBus: ComposerEventBus,
        mode: ComposerMode = .newPost
    ) {
        self.messages = messages
        self.eventBus = eventBus
        self.mode = mode
        switch mode {
        case .newPost:
            self.body = ""
            self.tagsInput = ""
            self.visibility = .public
        case .edit(_, let original):
            self.body = original.text
            self.tagsInput = original.tags.joined(separator: " ")
            self.visibility = original.visibility
        }
    }

    // MARK: - Intents

    /// Toggles between public and private. Bound to the visibility
    /// segment / picker in the view.
    func setVisibility(_ visibility: Visibility) {
        self.visibility = visibility
    }

    /// Submits the post. Validates `isPublishable` first; bails out
    /// silently if invalid (the view's publish button is disabled in
    /// that case, but defence-in-depth never hurts). On success posts
    /// a `ComposerEvent` and flips `didFinish` so the window dismisses.
    func submit() async {
        guard isPublishable, !isSubmitting else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        let normalisedTags = Self.normalise(tags: tagsInput)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch mode {
            case .newPost:
                let created = try await messages.create(
                    body: trimmedBody,
                    parentId: nil,
                    tags: normalisedTags,
                    visibility: visibility,
                    pushedMessageId: nil
                )
                eventBus.post(.messageCreated(created))
                didFinish = true
            case .edit(let id, _):
                let updated = try await messages.update(
                    messageId: id,
                    body: trimmedBody,
                    tags: normalisedTags,
                    visibility: visibility
                )
                eventBus.post(.messageUpdated(updated))
                didFinish = true
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Tag normalisation

    /// Splits the raw input on commas / whitespace and trims a leading
    /// `#` so users can type either form. Order is preserved; duplicates
    /// are dropped to avoid sending the same tag twice.
    static func normalise(tags input: String) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        let separators = CharacterSet(charactersIn: ", \t\n")
        for raw in input.components(separatedBy: separators) {
            var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.hasPrefix("#") { token.removeFirst() }
            guard !token.isEmpty else { continue }
            if seen.insert(token).inserted {
                ordered.append(token)
            }
        }
        return ordered
    }
}
