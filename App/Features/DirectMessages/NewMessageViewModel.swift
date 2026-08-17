// NewMessageViewModel
//
// Backs the "New message" composer sheet (work-consolidation.md G1). Loads the set
// of eligible recipients (mutual followers) via `recipients()`, tracks the
// selection + body draft, and sends. Reads through
// `DirectMessagesServicing` only so unit tests substitute a stub service.
//
// Send validation: a blank body (whitespace-only, no images) is rejected
// before the service is touched — the "invalid input rejected before the
// service is called" gate. A send with no selected recipient is likewise
// rejected locally. On success the sheet reports the recipient's username
// so the caller can open the thread; the bus is notified so open list /
// thread surfaces update in place.
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

    // MARK: - Observable state

    /// The eligible recipients (mutual followers) from `recipients()`.
    private(set) var recipients: [UserSummary] = []

    /// The selected recipient's id, or `nil` before a pick. The picker
    /// binds to this.
    var selectedRecipientId: String?

    /// The message body draft. Two-way bound by the sheet.
    var body: String = ""

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
        selectedRecipientId != nil
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Init

    init(
        service: DirectMessagesServicing,
        eventBus: DirectMessagesEventBus? = nil
    ) {
        self.service = service
        self.bus = eventBus
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

    /// Sends the drafted message to the selected recipient. Rejects a
    /// missing recipient or a blank body before the service is touched.
    /// On success sets `sentMessage` and posts to the bus.
    func send() async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let recipientId = selectedRecipientId, !recipientId.isEmpty else {
            error = NewMessageError.noRecipient
            return
        }
        guard !trimmed.isEmpty else {
            error = NewMessageError.emptyBody
            return
        }
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await service.send(recipientId: recipientId, body: trimmed)
            sentMessage = sent
            error = nil
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
}

// MARK: - NewMessageError

/// Local validation errors raised before any service call.
enum NewMessageError: Error, Equatable {
    /// Send was invoked with no recipient selected.
    case noRecipient
    /// Send was invoked with a blank body.
    case emptyBody
}
