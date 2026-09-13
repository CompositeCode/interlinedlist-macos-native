// DMThreadViewModel
//
// Drives the thread column of `DirectMessagesRootView` (work-consolidation.md G1) —
// a resolved 1:1 conversation with one other user. Owns the rendered
// message list, the composer draft, the send action, the mark-read-on-
// open behaviour, and the live `threadUpdates` poll. Reads through
// `DirectMessagesServicing` only so unit tests substitute a stub service.
//
// Concurrency ownership:
//   - `startPolling()` (bound to the view's `.task` / `.onAppear`)
//     performs the initial `thread(...)` load, marks inbound messages
//     read, then loops `threadUpdates(...)` every `pollInterval`, merging
//     new messages in place. The loop honours `Task.isCancelled`.
//   - `stopPolling()` (bound to `.onDisappear`) cancels the loop task.
//   The poll task is owned by this view model, captured `[weak self]`,
//   and never relies on `deinit`-time cancellation (Observation-macro
//   semantics — mirrors `CurrentUserStore` / `SearchViewModel`).
//
// Optimistic send (per the swift-engineer skill): a blank draft (no text,
// no images) is rejected before the service is touched. On send we append
// an optimistic placeholder keyed by a temporary id, call the service,
// and on success replace the placeholder with the server's authoritative
// `DirectMessage` (never trusting the local copy). On failure we remove
// the placeholder, restore the draft, and surface the error.
//
// Photo attachments (work-consolidation.md G22): up to 8 per message, held
// in a `DMAttachmentDraft` and uploaded through
// `DirectMessagesServicing.uploadImage` immediately before the send. An
// upload that fails does NOT abort the message — the text still goes out,
// the failure is surfaced, and nothing the user typed or picked is lost.
// Photo sending requires a verified email; the server's 403 is surfaced
// verbatim. TODO(#41): the verification gate is owned by issue #41.
//
// Bubble alignment uses `DirectMessage.isOutgoing(currentUserId:)` with
// the id from the injected `currentUserID` closure so the view model
// always sees the latest session (mirrors `ProfileViewModel`).
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class DMThreadViewModel {

    // MARK: - Configuration

    /// How often the visible thread polls `threadUpdates`. Tests inject a
    /// tiny interval (or drive updates manually) so they don't wait 5s.
    static let defaultPollInterval: Duration = .seconds(6)

    // MARK: - Subject

    /// The other participant's username — the thread key.
    let username: String

    // MARK: - Dependencies

    private let service: DirectMessagesServicing
    private let bus: DirectMessagesEventBus?
    private let currentUserIDProvider: @MainActor () -> String?
    private let pollInterval: Duration

    /// Reads an attachment's bytes. Injected so tests exercise the upload
    /// path without touching the filesystem (mirrors `ComposerViewModel`).
    private let readData: @Sendable (URL) async throws -> Data

    // MARK: - Observable state

    /// The rendered thread, oldest-first (chat order — newest at the
    /// bottom). The server returns a `DMThread`; we normalise order once
    /// on load and append in place thereafter.
    private(set) var messages: [DirectMessage] = []

    /// The resolved other user, populated from the first `thread(...)`.
    private(set) var otherUser: UserSummary?

    /// Whether the two users mutually follow (server-reported). When
    /// `false`, the composer is disabled — a non-mutual can't be messaged.
    private(set) var isMutual: Bool = false

    /// Whether the current user has blocked (or is blocked by) the other.
    /// When `true`, the composer is disabled.
    private(set) var isBlocked: Bool = false

    /// Cursor for loading older messages, or `nil` when the head is
    /// reached.
    private(set) var olderCursor: String?

    /// The composer draft. Two-way bound by the view.
    var draft: String = ""

    /// Pending photo attachments for the next send (G22).
    private(set) var attachmentDraft = DMAttachmentDraft()

    /// The pending photos, for the composer's thumbnail strip.
    var attachments: [ComposerAttachment] { attachmentDraft.attachments }

    /// Whether the documented 8-photo cap is reached — disables the attach
    /// affordance rather than letting a pick fail after the fact.
    var attachmentsAreFull: Bool { attachmentDraft.isFull }

    /// The documented per-message photo cap, for the composer's counter.
    var maxAttachments: Int { DMLimits.maxImagesPerMessage }

    /// The documented DM body ceiling — 10,000 characters, far larger than
    /// the post composer's 5,000 (a different surface, a different limit).
    var bodyCharacterLimit: Int { DMLimits.maxBodyCharacters }

    /// True when the draft exceeds the body ceiling.
    var isOverBodyLimit: Bool { draft.count > bodyCharacterLimit }

    /// True while the initial thread load is in flight.
    private(set) var isLoading: Bool = false

    /// True while a send round-trip is in flight.
    private(set) var isSending: Bool = false

    /// Surfaced error from the most recent failed load / send. Polling
    /// failures are swallowed (a dropped poll should not error the UI).
    private(set) var error: Error?

    /// True once the initial load resolved (success or failure).
    private(set) var hasLoadedOnce: Bool = false

    /// Whether the composer can currently send: mutual, not blocked, and
    /// a non-blank draft.
    var canSend: Bool {
        guard isMutual, !isBlocked, !isOverBodyLimit else { return false }
        // A photo alone is a valid message — the server accepts imageUrls
        // with an empty body — so either a non-blank body or a queued photo
        // is enough.
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachmentDraft.isEmpty
    }

    // MARK: - Internals

    /// Owns the polling loop so `stopPolling()` cancels it. `[weak self]`
    /// capture; no `deinit`-time cancel (Observation-macro semantics).
    private var pollTask: Task<Void, Never>?

    /// The recipient user id, learned from the first inbound/outbound
    /// message or the resolved other user. Needed to `send`.
    private var recipientId: String?

    /// Monotonic temp-id source for optimistic placeholders.
    private var optimisticSeq: Int = 0

    // MARK: - Init

    init(
        username: String,
        service: DirectMessagesServicing,
        eventBus: DirectMessagesEventBus? = nil,
        currentUserID: @MainActor @escaping () -> String? = { nil },
        pollInterval: Duration = defaultPollInterval,
        readData: @escaping @Sendable (URL) async throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.username = username
        self.service = service
        self.bus = eventBus
        self.currentUserIDProvider = currentUserID
        self.pollInterval = pollInterval
        self.readData = readData
    }

    // MARK: - Lifecycle

    /// Loads the thread, marks inbound messages read, and starts the
    /// live poll. Bound to the view's `.task`. Idempotent — re-entry
    /// replaces the prior poll task.
    func startPolling() async {
        await load()
        await markInboundRead()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop()
        }
    }

    /// Cancels the poll loop. Bound to `.onDisappear`. Idempotent.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Load

    /// Initial thread load. Normalises to oldest-first and captures the
    /// other user / mutual / blocked flags and the recipient id.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let thread = try await service.thread(username: username, cursor: nil)
            apply(thread, replacing: true)
            error = nil
            hasLoadedOnce = true
        } catch is CancellationError {
            // The load was cancelled (view teardown / navigation), not
            // failed. Leave `error` and `hasLoadedOnce` untouched so no
            // banner shows and no "loaded" flags flip prematurely — the
            // surviving poll (or a fresh load) repopulates the thread.
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
    }

    // MARK: - Send

    /// Queues picked / dropped photos for the next send. Non-images and
    /// anything past the documented 8-photo cap are refused here, before any
    /// bytes are read — the "invalid input rejected before the service is
    /// called" gate.
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

    /// Sends the current draft. Blank drafts (no text, no photos) are
    /// rejected before the service is touched — `canSend` gates the UI but
    /// this guard makes the rejection authoritative. Optimistic: append a
    /// placeholder, call `send`, replace it with the server message on
    /// success, or remove it and restore the draft on failure.
    ///
    /// Photos upload first (G22). A failed upload is **not** fatal: whatever
    /// uploaded is attached, the failure is surfaced, and a message with text
    /// still goes out. Only a photos-only message whose every upload failed
    /// has nothing left to send — then the draft and the picks are kept
    /// intact so the user can retry.
    func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingAttachments = attachmentDraft
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }
        guard !isOverBodyLimit else {
            error = DMThreadError.bodyTooLong(limit: bodyCharacterLimit)
            return
        }
        guard let recipientId = resolvedRecipientId() else {
            // No recipient id could be resolved (empty thread with no
            // resolved other user). Surface a typed error rather than
            // firing a doomed request.
            error = DMThreadError.unknownRecipient
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

        // Every photo failed on a photos-only message: there is nothing left
        // to send. Keep the draft and the picks, surface the failure.
        guard !trimmed.isEmpty || !imageURLs.isEmpty else {
            error = uploadFailure
            return
        }

        // 2. Optimistic placeholder, now including any uploaded photos.
        optimisticSeq += 1
        let tempId = "optimistic-\(optimisticSeq)"
        let me = currentUserIDProvider()
        let placeholder = DirectMessage(
            id: tempId,
            senderId: me ?? "",
            recipientId: recipientId,
            body: trimmed,
            imageURLs: imageURLs.compactMap(URL.init(string:)),
            createdAt: Date(),
            readAt: nil,
            sender: nil,
            recipient: otherUser
        )
        messages.append(placeholder)
        let priorDraft = draft
        draft = ""

        do {
            let sent = try await service.send(
                recipientId: recipientId,
                body: trimmed,
                imageURLs: imageURLs
            )
            // Replace the placeholder with the authoritative server value.
            if let index = messages.firstIndex(where: { $0.id == tempId }) {
                messages[index] = sent
            } else {
                messages.append(sent)
            }
            attachmentDraft.removeAll()
            // A partial photo failure is still worth reporting even though
            // the message went out — otherwise a photo silently vanishes.
            error = uploadFailure
            bus?.post(.messageSent(recipientUsername: username, message: sent))
        } catch is CancellationError {
            // Cancelled mid-send — not a failure. Drop the optimistic bubble
            // and restore the draft so the user can retry; a live poll
            // reconciles any message that did reach the server. No banner.
            messages.removeAll { $0.id == tempId }
            draft = priorDraft
        } catch {
            messages.removeAll { $0.id == tempId }
            draft = priorDraft
            self.error = error
        }
    }

    // MARK: - Mark read

    /// Marks every unread inbound message read, then posts `threadRead`
    /// and re-publishes the server unread count so peer surfaces update.
    /// Soft-fails per message: one failed mark-read does not error the UI.
    func markInboundRead() async {
        let me = currentUserIDProvider()
        let unread = messages.filter { isUnreadInbound($0, me: me) }
        guard !unread.isEmpty else { return }
        var didMarkAny = false
        for message in unread {
            do {
                try await service.markRead(id: message.id)
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = withReadAt(messages[index], date: Date())
                }
                didMarkAny = true
            } catch {
                // Soft — leave the message unread; a later poll / reopen
                // retries.
            }
        }
        if didMarkAny {
            bus?.post(.threadRead(username: username))
            await republishUnreadCount()
        }
    }

    // MARK: - Poll

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                // Cancelled during sleep.
                return
            }
            guard !Task.isCancelled else { return }
            await pollOnce()
        }
    }

    /// One `threadUpdates` fetch, merged in place. Visible for tests so a
    /// poll cycle can be driven deterministically without waiting out the
    /// interval. Marks any newly-arrived inbound messages read.
    func pollOnce() async {
        do {
            let update = try await service.threadUpdates(username: username, since: newestId)
            // A successful round-trip proves the thread is live — clear any
            // stale error (e.g. a cancelled initial load) so a one-off
            // cancellation banner self-heals instead of pinning forever.
            error = nil
            guard !update.messages.isEmpty || update.otherUser != nil else { return }
            mergeUpdates(update)
            await markInboundRead()
        } catch {
            // Swallow — a dropped poll must not surface an error to the UI.
        }
    }

    // MARK: - Merge

    private func apply(_ thread: DMThread, replacing: Bool) {
        let ordered = thread.messages.sorted { $0.createdAt < $1.createdAt }
        if replacing {
            messages = ordered
        } else {
            mergeMessages(ordered)
        }
        if let other = thread.otherUser { otherUser = other }
        isMutual = thread.isMutual
        isBlocked = thread.isBlocked
        olderCursor = thread.olderCursor
        cacheRecipientId()
    }

    private func mergeUpdates(_ thread: DMThread) {
        mergeMessages(thread.messages)
        if let other = thread.otherUser { otherUser = other }
        // `threadUpdates` reflects live mutual / block changes too.
        isMutual = thread.isMutual
        isBlocked = thread.isBlocked
        cacheRecipientId()
    }

    /// Merges `incoming` into `messages` by id, preserving oldest-first
    /// order. New ids are appended (and the list re-sorted by time);
    /// existing ids are updated in place (e.g. a read-receipt landing).
    private func mergeMessages(_ incoming: [DirectMessage]) {
        guard !incoming.isEmpty else { return }
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        var appended = false
        for message in incoming {
            if byId[message.id] != nil {
                byId[message.id] = message
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = message
                }
            } else {
                byId[message.id] = message
                messages.append(message)
                appended = true
            }
        }
        if appended {
            messages.sort { $0.createdAt < $1.createdAt }
        }
    }

    // MARK: - Helpers

    /// Newest message id, used as the `since` token for `threadUpdates`.
    private var newestId: String? { messages.last?.id }

    private func republishUnreadCount() async {
        do {
            let count = try await service.unreadCount()
            bus?.post(.unreadCountChanged(count))
        } catch {
            // Soft.
        }
    }

    private func resolvedRecipientId() -> String? {
        cacheRecipientId()
        return recipientId
    }

    /// Derives the recipient id from the resolved other user or from the
    /// non-me side of any message. Cached once known.
    private func cacheRecipientId() {
        if let recipientId, !recipientId.isEmpty { return }
        if let id = otherUser?.id, !id.isEmpty {
            recipientId = id
            return
        }
        let me = currentUserIDProvider()
        for message in messages {
            if let me {
                let otherId = message.senderId == me ? message.recipientId : message.senderId
                if !otherId.isEmpty { recipientId = otherId; return }
            } else if !message.senderId.isEmpty {
                recipientId = message.senderId
                return
            }
        }
    }

    private func isUnreadInbound(_ message: DirectMessage, me: String?) -> Bool {
        guard !message.isRead else { return false }
        guard let me else { return message.senderId != (otherUser?.id ?? "") ? false : true }
        return message.recipientId == me
    }

    private func withReadAt(_ message: DirectMessage, date: Date) -> DirectMessage {
        DirectMessage(
            id: message.id,
            senderId: message.senderId,
            recipientId: message.recipientId,
            body: message.body,
            imageURLs: message.imageURLs,
            createdAt: message.createdAt,
            readAt: message.readAt ?? date,
            sender: message.sender,
            recipient: message.recipient
        )
    }

    // MARK: - Test seam

    /// Seeds the rendered thread without a service call. For tests / previews.
    func seedForTest(
        messages: [DirectMessage],
        otherUser: UserSummary? = nil,
        isMutual: Bool = true,
        isBlocked: Bool = false
    ) {
        self.messages = messages.sorted { $0.createdAt < $1.createdAt }
        self.otherUser = otherUser
        self.isMutual = isMutual
        self.isBlocked = isBlocked
        self.hasLoadedOnce = true
        cacheRecipientId()
    }

    /// Seeds pending photo attachments without going through the file
    /// picker. For tests / previews.
    func seedAttachmentsForTest(urls: [URL]) {
        _ = attachmentDraft.add(urls: urls)
    }
}

// MARK: - DMThreadError

/// Local validation errors raised before any service call.
enum DMThreadError: Error, Equatable {
    /// `send` was invoked but no recipient id could be resolved (an empty
    /// thread with no resolved other user).
    case unknownRecipient
    /// The draft exceeded the documented 10,000-character DM ceiling.
    case bodyTooLong(limit: Int)
}

extension DMThreadError: LocalizedError, CustomStringConvertible {
    var errorDescription: String? { description }
    var description: String {
        switch self {
        case .unknownRecipient:
            return "We couldn't work out who this conversation is with."
        case .bodyTooLong(let limit):
            return "A direct message can be up to \(limit) characters."
        }
    }
}
