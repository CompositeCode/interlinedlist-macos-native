// NewMessageViewModel
//
// Backs the "New message" composer sheet (work-consolidation.md G1). Loads the set
// of eligible recipients (mutual followers) via `recipients()`, tracks the
// selection + body draft, and sends. Reads through
// `DirectMessagesServicing` only so unit tests substitute a stub service.
//
// Send validation: a blank body (whitespace-only, no photos) is rejected
// before the service is touched — the "invalid input rejected before the
// service is called" gate. A send with no selected recipient is likewise
// rejected locally. On success the sheet reports the recipient's username
// so the caller can open the thread; the bus is notified so open list /
// thread surfaces update in place.
//
// Photo attachments (work-consolidation.md G22): up to 8 per message via a
// shared `DMAttachmentDraft`, uploaded immediately before the send. A
// failed upload never costs the user their draft — the text still sends
// and the failure is surfaced. Photo sending requires a verified email;
// the server's 403 is surfaced verbatim. TODO(#41): the verification gate
// is owned by issue #41 — do not add a second check here.
//
// The recipient list is the mutual-follower set (`recipients()`), which is
// why the empty state explains the mutual-follow rule rather than just
// saying the list is empty.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class NewMessageViewModel {

    // MARK: - Dependencies

    private let service: DirectMessagesServicing
    private let bus: DirectMessagesEventBus?

    /// Reads an attachment's bytes. Injected so tests exercise the upload
    /// path without touching the filesystem (mirrors `ComposerViewModel`).
    private let readData: @Sendable (URL) async throws -> Data

    // MARK: - Observable state

    /// The eligible recipients (mutual followers) from `recipients()`.
    private(set) var recipients: [UserSummary] = []

    /// The selected recipient's id, or `nil` before a pick. The picker
    /// binds to this.
    var selectedRecipientId: String?

    /// The message body draft. Two-way bound by the sheet.
    var body: String = ""

    /// Pending photo attachments for this message (G22).
    private(set) var attachmentDraft = DMAttachmentDraft()

    /// The pending photos, for the sheet's thumbnail strip.
    var attachments: [ComposerAttachment] { attachmentDraft.attachments }

    /// Whether the documented 8-photo cap is reached.
    var attachmentsAreFull: Bool { attachmentDraft.isFull }

    /// The documented per-message photo cap, for the sheet's counter.
    var maxAttachments: Int { DMLimits.maxImagesPerMessage }

    /// The documented DM body ceiling — 10,000 characters. Deliberately not
    /// the post composer's `GET /api/limits` message length (5,000 live on
    /// 2026-09-09): DMs are a separate, larger surface.
    var bodyCharacterLimit: Int { DMLimits.maxBodyCharacters }

    /// True when the draft exceeds the body ceiling.
    var isOverBodyLimit: Bool { body.count > bodyCharacterLimit }

    /// True while the recipient list is loading.
    private(set) var isLoadingRecipients: Bool = false

    /// True while the send round-trip is in flight.
    private(set) var isSending: Bool = false

    /// Surfaced error from the most recent failed load / send.
    private(set) var error: Error?

    /// Set to the message the send produced, so the sheet can dismiss and
    /// the caller can open the thread. `nil` until a successful send.
    private(set) var sentMessage: DirectMessage?

    /// True once the recipient load resolved (success or failure).
    private(set) var hasLoadedRecipients: Bool = false

    /// Whether send is currently possible: a recipient is picked and the
    /// body is non-blank.
    var canSend: Bool {
        guard selectedRecipientId != nil, !isOverBodyLimit else { return false }
        // A photo alone is a valid message, so either a non-blank body or a
        // queued photo is enough.
        return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachmentDraft.isEmpty
    }

    // MARK: - Init

    init(
        service: DirectMessagesServicing,
        eventBus: DirectMessagesEventBus? = nil,
        readData: @escaping @Sendable (URL) async throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.service = service
        self.bus = eventBus
        self.readData = readData
    }

    // MARK: - Intents

    /// Loads the eligible recipient list. If a `preselectUsername` is
    /// supplied (the "Message" button on a profile), the matching
    /// recipient is auto-selected once the list resolves.
    func loadRecipients(preselectUsername: String? = nil) async {
        guard !isLoadingRecipients else { return }
        isLoadingRecipients = true
        defer { isLoadingRecipients = false }
        do {
            let list = try await service.recipients()
            recipients = list
            error = nil
            hasLoadedRecipients = true
            if let preselectUsername,
               let match = list.first(where: { $0.username == preselectUsername }) {
                selectedRecipientId = match.id
            }
        } catch {
            self.error = error
            hasLoadedRecipients = true
        }
    }

    /// Queues picked / dropped photos. Non-images and anything past the
    /// documented 8-photo cap are refused here, before any bytes are read —
    /// the "invalid input rejected before the service is called" gate.
    func addAttachments(urls: [URL]) {
        if let rejection = attachmentDraft.add(urls: urls) {
            error = rejection
        } else {
            error = nil
        }
    }

    /// Removes one queued photo.
    func removeAttachment(id: ComposerAttachment.ID) {
        attachmentDraft.remove(id: id)
    }

    /// Sends the drafted message to the selected recipient. Rejects a
    /// missing recipient, an over-long body, or a blank message before the
    /// service is touched. On success sets `sentMessage` and posts to the bus.
    ///
    /// Photos upload first (G22). A failed upload is not fatal: whatever
    /// uploaded is attached, the failure is surfaced, and a message with text
    /// still goes out. A photos-only message whose every upload failed has
    /// nothing to send — the draft and the picks are kept for a retry.
    func send() async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingAttachments = attachmentDraft
        guard let recipientId = selectedRecipientId, !recipientId.isEmpty else {
            error = NewMessageError.noRecipient
            return
        }
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else {
            error = NewMessageError.emptyBody
            return
        }
        guard !isOverBodyLimit else {
            error = NewMessageError.bodyTooLong(limit: bodyCharacterLimit)
            return
        }
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }

        // 1. Upload photos, if any. Never throws — see `DMAttachmentDraft`.
        var uploadFailure: Error?
        var imageURLs: [String] = []
        if !pendingAttachments.isEmpty {
            let result = await pendingAttachments.upload(using: service, readData: readData)
            imageURLs = result.urls
            uploadFailure = result.failure
        }

        // Every photo failed on a photos-only message: nothing left to send.
        guard !trimmed.isEmpty || !imageURLs.isEmpty else {
            error = uploadFailure
            return
        }

        do {
            let sent = try await service.send(
                recipientId: recipientId,
                body: trimmed,
                imageURLs: imageURLs
            )
            sentMessage = sent
            attachmentDraft.removeAll()
            // A partial photo failure is still reported even though the
            // message went out — otherwise a photo silently vanishes.
            error = uploadFailure
            if let username = recipients.first(where: { $0.id == recipientId })?.username {
                bus?.post(.messageSent(recipientUsername: username, message: sent))
            }
        } catch is CancellationError {
            // Cancelled mid-send — not a failure. Leave `error` nil so the
            // sheet shows no spurious "Network error" banner; the user can
            // retry (a persisted message reconciles via the list poll).
        } catch {
            self.error = error
        }
    }

    /// The username of the currently-selected recipient, for the caller to
    /// open the thread after a successful send.
    var selectedRecipientUsername: String? {
        guard let id = selectedRecipientId else { return nil }
        return recipients.first(where: { $0.id == id })?.username
    }

    /// Seeds the recipient list without a service call. For tests / previews.
    func seedRecipientsForTest(_ list: [UserSummary]) {
        recipients = list
        hasLoadedRecipients = true
    }
}

// MARK: - NewMessageError

/// Local validation errors raised before any service call.
enum NewMessageError: Error, Equatable {
    /// Send was invoked with no recipient selected.
    case noRecipient
    /// Send was invoked with a blank body and no photos.
    case emptyBody
    /// The body exceeded the documented 10,000-character DM ceiling.
    case bodyTooLong(limit: Int)
}

extension NewMessageError: LocalizedError, CustomStringConvertible {
    var errorDescription: String? { description }
    var description: String {
        switch self {
        case .noRecipient:
            return "Choose someone to message first."
        case .emptyBody:
            return "A message needs text or a photo before it can be sent."
        case .bodyTooLong(let limit):
            return "A direct message can be up to \(limit) characters."
        }
    }
}
