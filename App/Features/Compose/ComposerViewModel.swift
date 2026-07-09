// ComposerViewModel
//
// Drives the composer window for new messages and edits (PLAN.md §6 M2 —
// "Composer window"; §6 M6 — media / scheduled / cross-post). The view
// is a thin shell: this owns the body text, the tag-input string, the
// visibility toggle, the M6 attachment / schedule / cross-post state,
// the `isSubmitting` flag, and the validation rule for empty body.
//
// On submit:
//   • `.edit` → `MessagesServicing.update` (M6 fields don't apply to an
//     edit — the composer surfaces them only for new messages).
//   • `.newPost` → upload each attachment to get its hosted URL, then
//     `MessagesServicing.createPost` with the full M6 field set. The
//     domain service gates media / schedule / cross-post before the HTTP
//     call; this view model also gates the *UI* (controls disabled for
//     non-subscribers) so the user never reaches an "enabled but broken"
//     control (PLAN.md §6 M2 rule).
//
// On a gated `createPost` returning a 403 (subscription lapsed
// mid-session, PLAN.md §8), `onSubscriberLapse` is invoked so the
// composition root can re-fetch `customerStatus` and the UI re-gates.
//
// Reply and repost are not driven by this view model — reply lives
// inline at the bottom of `MessageDetailView`, and repost goes through
// a small sheet on the row.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

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

    /// The current account's entitlements, used for the *UI* gate (controls
    /// disabled + upsell hint for non-subscribers). Authoritative for UX; the
    /// domain `MessagesService` enforces the same status as a backstop.
    private(set) var entitlements: EntitlementsService

    /// Reads a local file's bytes at send time. Injected so tests can supply
    /// bytes without touching the filesystem; production reads the file URL.
    private let readData: @Sendable (URL) async throws -> Data

    /// Invoked when a gated write surfaces a subscription lapse (403 /
    /// `.subscriberRequired`) so the composition root can re-fetch
    /// `customerStatus` and the UI re-gates (PLAN.md §8). Optional — `nil` in
    /// tests that don't assert the refresh hook.
    private let onSubscriberLapse: (@MainActor () async -> Void)?

    private let userService: UserServicing?

    // MARK: - Editable state

    /// Body text of the message. Markdown source — treated as plain text here
    /// (no toolbar) per PLAN.md §6 M2.
    var body: String

    /// Free-form tag input. Split on commas / whitespace; `#` stripped;
    /// empty tokens dropped. Held raw so typing isn't interrupted by
    /// re-normalisation.
    var tagsInput: String

    /// Public or private visibility.
    var visibility: Visibility

    // MARK: - M6 editable state

    /// Pending media attachments (local file URLs). Uploaded at send time.
    private(set) var attachments: [ComposerAttachment] = []

    /// Whether the message is scheduled for the future rather than sent now.
    /// Toggling on seeds `scheduledAt` with a near-future default.
    var isScheduled: Bool = false

    /// The future publish time when `isScheduled`. Ignored when scheduling is
    /// off. Defaults to one hour out so the picker opens on a valid value.
    var scheduledAt: Date

    /// Cross-post targets. Mastodon is a single enable + comma/space-separated
    /// provider-id entry (v1 — see note in the file header / report). Bluesky
    /// and LinkedIn are simple booleans the API takes directly.
    var crossPostToMastodon: Bool = false
    var mastodonProviderIdsInput: String = ""
    var crossPostToBluesky: Bool = false
    var crossPostToLinkedIn: Bool = false

    // MARK: - Read-only state

    /// True while a submit round-trip (uploads + create / update) is in flight.
    private(set) var isSubmitting: Bool = false

    /// The last submission error. Cleared on the next submit.
    private(set) var error: Error?

    /// Set to `true` after a successful publish; the window observes this to
    /// dismiss itself.
    private(set) var didFinish: Bool = false

    /// Per-platform cross-post results from the last successful publish (NW-2).
    /// Non-nil when the server returned at least one cross-post outcome; the
    /// view presents `CrossPostResultsSheet` while this is non-nil.
    private(set) var crossPostResults: [CrossPostResult]?

    /// True when the Bluesky cross-post toggle was enabled but Bluesky is not
    /// configured on the server (NW-4). The composer shows an inline hint.
    private(set) var blueskyNotConfigured: Bool = false

    /// True when a Mastodon cross-post toggle was enabled but Mastodon is not
    /// configured for that instance (NW-4).
    private(set) var mastodonNotConfigured: Bool = false

    // MARK: - Derived gating

    /// Whether the account may use the subscriber-gated M6 controls. Drives the
    /// disabled state + upsell hint in the view; the controls render visible-
    /// but-disabled so the features stay discoverable (PLAN.md §6 M2 rule).
    var canUseSubscriberFeatures: Bool {
        entitlements.isSubscriber
    }

    /// Whether the M6 controls should appear at all. Edits don't expose media /
    /// schedule / cross-post — those apply to a fresh message only.
    var showsSubscriberControls: Bool {
        if case .newPost = mode { return true }
        return false
    }

    /// The primary-action label. Reflects the schedule-vs-send-now affordance
    /// (PLAN.md §6 M6) for a new message; falls back to the mode's label for an
    /// edit.
    var publishButtonLabel: String {
        if showsSubscriberControls, isScheduled {
            return "Schedule"
        }
        return mode.publishButtonLabel
    }

    // MARK: - Validation

    /// Whether the current draft would be accepted for submit. Empty body is
    /// rejected by the composer (a new message / edit always needs text). A
    /// future-only schedule is also required when scheduling is on.
    var isPublishable: Bool {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if showsSubscriberControls, isScheduled, scheduledAt <= Date() {
            return false
        }
        return true
    }

    // MARK: - Init

    init(
        messages: MessagesServicing,
        eventBus: ComposerEventBus,
        mode: ComposerMode = .newPost,
        entitlements: EntitlementsService = EntitlementsService(customerStatus: .free),
        readData: @escaping @Sendable (URL) async throws -> Data = { try Data(contentsOf: $0) },
        onSubscriberLapse: (@MainActor () async -> Void)? = nil,
        userService: UserServicing? = nil
    ) {
        self.messages = messages
        self.eventBus = eventBus
        self.mode = mode
        self.entitlements = entitlements
        self.readData = readData
        self.onSubscriberLapse = onSubscriberLapse
        self.userService = userService
        self.scheduledAt = Date().addingTimeInterval(3600)
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

    func setVisibility(_ visibility: Visibility) {
        self.visibility = visibility
    }

    /// Adds picked / dropped file URLs as attachments. Unsupported file types
    /// are surfaced as an error rather than silently dropped. No-op for
    /// non-subscribers (the affordance is disabled in the view, but this is
    /// defence-in-depth so a programmatic add can't bypass the gate's intent).
    func addAttachments(urls: [URL]) {
        guard canUseSubscriberFeatures else {
            error = MessagesError.subscriberRequired(.mediaAttachments)
            return
        }
        var rejected = false
        for url in urls {
            if let attachment = ComposerAttachment(url: url) {
                attachments.append(attachment)
            } else {
                rejected = true
            }
        }
        if rejected {
            error = ComposerError.unsupportedAttachment
        }
    }

    /// Removes one queued attachment by id.
    func removeAttachment(id: ComposerAttachment.ID) {
        attachments.removeAll { $0.id == id }
    }

    /// Submits the draft. Validates `isPublishable` first; bails silently if
    /// invalid (the publish button is disabled, but defence-in-depth). For a
    /// new message: uploads each attachment, then calls `createPost` with the full
    /// M6 field set. For an edit: calls `update`. On success posts a
    /// `ComposerEvent` and flips `didFinish`.
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
                try await submitNewPost(body: trimmedBody, tags: normalisedTags)
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
            await handle(error: error)
        }
    }

    // MARK: - New-message pipeline

    private func submitNewPost(body trimmedBody: String, tags: [String]) async throws {
        // 1. Upload media. Images and videos run through their own gated
        //    upload methods; the returned hosted URLs are what `createPost`
        //    references. Throws (and aborts the post) if any upload fails.
        var imageURLs: [String] = []
        var videoURLs: [String] = []
        for attachment in attachments {
            let bytes = try await readData(attachment.url)
            switch attachment.kind {
            case .image:
                imageURLs.append(try await messages.uploadImage(bytes))
            case .video:
                videoURLs.append(
                    try await messages.uploadVideo(bytes, contentType: attachment.videoContentType)
                )
            }
        }

        // 2. Resolve the M6 field set from the current controls.
        let scheduled: Date? = isScheduled ? scheduledAt : nil
        let mastodonProviderIds = crossPostToMastodon
            ? Self.normalise(providerIds: mastodonProviderIdsInput)
            : []

        // 3. Create the post. The domain service gates media / schedule /
        //    cross-post before the HTTP call; the UI gate above keeps the user
        //    from reaching here un-entitled in the normal flow.
        let created = try await messages.createPost(
            body: trimmedBody,
            tags: tags,
            visibility: visibility,
            imageURLs: imageURLs,
            videoURLs: videoURLs,
            scheduledAt: scheduled,
            mastodonProviderIds: mastodonProviderIds,
            crossPostToBluesky: crossPostToBluesky,
            crossPostToLinkedIn: crossPostToLinkedIn
        )
        eventBus.post(.messageCreated(created))
        if !created.crossPostResults.isEmpty {
            crossPostResults = created.crossPostResults
        }
        didFinish = true
    }

    // MARK: - Error handling

    /// Surfaces the error and, when it signals a subscription lapse, asks the
    /// composition root to re-fetch `customerStatus` so the UI re-gates
    /// (PLAN.md §8). A `.subscriberRequired` domain error or a 403-style API
    /// error both trigger the refresh.
    private func handle(error: Error) async {
        self.error = error
        if Self.signalsSubscriberLapse(error) {
            await onSubscriberLapse?()
        }
    }

    /// Whether `error` indicates the account lost (or never had) entitlement
    /// mid-flow. The domain gate throws `.subscriberRequired`; a server-side
    /// lapse surfaces as a 403 in the error's text. We match conservatively on
    /// both so the refresh hook fires for either.
    private static func signalsSubscriberLapse(_ error: Error) -> Bool {
        if case MessagesError.subscriberRequired = error { return true }
        let text = error.localizedDescription.lowercased()
        return text.contains("403") || text.contains("forbidden") || text.contains("subscri")
    }

    // MARK: - Tag normalisation

    /// Splits the raw input on commas / whitespace and trims a leading `#`.
    /// Order preserved; duplicates dropped.
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

    /// Splits Mastodon provider-id input on commas / whitespace. No `#`
    /// stripping (provider ids are opaque). Order preserved; duplicates dropped.
    static func normalise(providerIds input: String) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        let separators = CharacterSet(charactersIn: ", \t\n")
        for raw in input.components(separatedBy: separators) {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            if seen.insert(token).inserted {
                ordered.append(token)
            }
        }
        return ordered
    }

    // MARK: - Cross-post configuration checks (NW-4)

    /// Called when the user enables the Bluesky cross-post toggle. Checks whether
    /// Bluesky is configured on the server; if not, disables the toggle and sets
    /// `blueskyNotConfigured = true` so the view can show a hint (NW-4).
    func setBlueskyEnabled(_ enabled: Bool) async {
        crossPostToBluesky = enabled
        blueskyNotConfigured = false
        guard enabled, let userService else { return }
        do {
            let configured = try await userService.blueskyConfigured()
            if !configured {
                crossPostToBluesky = false
                blueskyNotConfigured = true
            }
        } catch {
            // Configuration check failure is non-fatal; leave the toggle as-is.
        }
    }

    /// Called when the user enables a Mastodon cross-post toggle. Checks whether
    /// Mastodon is configured for the resolved instance; if not, disables the
    /// toggle and sets `mastodonNotConfigured = true` (NW-4).
    func setMastodonEnabled(_ enabled: Bool) async {
        crossPostToMastodon = enabled
        mastodonNotConfigured = false
        guard enabled, let userService else { return }
        let instance = normalised(mastodonProviderIdsInput)
        guard !instance.isEmpty else { return }
        do {
            let configured = try await userService.mastodonConfigured(instance: instance)
            if !configured {
                crossPostToMastodon = false
                mastodonNotConfigured = true
            }
        } catch {
            // Non-fatal.
        }
    }

    /// Also expose a method to dismiss the cross-post results sheet.
    func dismissCrossPostResults() {
        crossPostResults = nil
    }

    private func normalised(_ input: String) -> String {
        input.components(separatedBy: CharacterSet(charactersIn: ", \t\n"))
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }
}

// MARK: - ComposerError

/// Composer-local errors that aren't domain errors — surfaced inline in the
/// composer's error banner.
enum ComposerError: Error, LocalizedError, Equatable {
    /// A picked / dropped file isn't a supported image or video type.
    case unsupportedAttachment

    var errorDescription: String? {
        switch self {
        case .unsupportedAttachment:
            return "That file isn't a supported image or video."
        }
    }
}
