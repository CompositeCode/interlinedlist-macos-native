// MessageDetailViewModel
//
// Drives `MessageDetailView`: loads a single message plus its first
// page of replies. Replies are kept flat for M1; the indented thread
// tree lands in a later milestone alongside richer threading
// affordances (PLAN.md §1, §6).
//
// Reads / writes through `MessagesServicing` only, so a stub service
// drives tests without any networking.
//
// M2 surface:
// - `postReply(body:tags:visibility:)` for the inline reply composer
//   at the bottom of the thread; appends the new reply to `replies`
//   on success without a full refetch.
// - `toggleDig(on:)` for the optimistic dig button on the detail
//   header and on each reply row. Mirrors `TimelineViewModel.toggleDig`.
// - `deleteCurrentMessage()` for the message-author's "Delete" menu
//   item. Sets `didDeleteRoot` so the view can dismiss / pop.
// - `apply(event:)` so reply / update / delete events from elsewhere
//   in the app flow into this view's state too.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class MessageDetailViewModel {

    static let pageSize: Int = 50

    private let messages: MessagesServicing
    private let messageID: String

    private(set) var message: Message?
    private(set) var replies: [Message] = []
    private(set) var isLoading: Bool = false
    private(set) var error: Error?

    /// True while a reply post is in flight. The view's inline
    /// composer's "Reply" button uses this to show progress and
    /// disable double-submit.
    private(set) var isPostingReply: Bool = false

    /// The most recent reply-post error. Surfaced inline in the
    /// reply composer so it doesn't clobber the load-time error.
    private(set) var replyError: Error?

    /// Flips true after the root message is successfully deleted, so
    /// the view knows to dismiss / pop the detail screen.
    private(set) var didDeleteRoot: Bool = false

    /// IDs of messages with an in-flight dig toggle. Prevents the
    /// same row from firing twice while the round-trip resolves.
    private var pendingDigOperations: Set<String> = []

    init(messages: MessagesServicing, messageID: String) {
        self.messages = messages
        self.messageID = messageID
    }

    // MARK: - Read

    /// Loads the message and its first page of replies in parallel.
    /// Either failure surfaces as `error` and the other half is still
    /// populated when it succeeds — partial results beat an empty
    /// detail screen.
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        async let messageResult = loadMessage()
        async let repliesResult = loadReplies()

        let (loadedMessage, loadedReplies) = await (messageResult, repliesResult)

        if let loadedMessage { self.message = loadedMessage }
        if let loadedReplies { self.replies = loadedReplies }
    }

    /// Re-fetches both halves; bound to the detail view's
    /// `.refreshable` modifier.
    func refresh() async {
        await load()
    }

    private func loadMessage() async -> Message? {
        do {
            return try await messages.message(id: messageID)
        } catch {
            self.error = error
            return nil
        }
    }

    private func loadReplies() async -> [Message]? {
        do {
            return try await messages.replies(of: messageID, limit: Self.pageSize, offset: 0)
        } catch {
            // Don't clobber a message-load error with a replies-load
            // error — the first failure is the more actionable one.
            if self.error == nil { self.error = error }
            return nil
        }
    }

    // MARK: - M2 — Inline reply

    /// Posts an inline reply to the loaded message. Validates a
    /// non-empty body. On success appends the new reply to `replies`
    /// without a full refetch; on failure surfaces `replyError` so
    /// the composer's "Reply" button can show the error inline.
    @discardableResult
    func postReply(
        body: String,
        tags: [String] = [],
        visibility: Visibility = .public
    ) async -> Message? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPostingReply else { return nil }

        isPostingReply = true
        replyError = nil
        defer { isPostingReply = false }

        do {
            let reply = try await messages.reply(
                to: messageID,
                body: trimmed,
                tags: tags,
                visibility: visibility
            )
            replies.append(reply)
            return reply
        } catch {
            self.replyError = error
            return nil
        }
    }

    // MARK: - M2 — Dig / undig with optimistic UI

    /// Optimistically flips the dig state on the supplied message (the
    /// root or any reply), then calls `dig` / `undig`. Rolls back on
    /// failure. The detail screen renders the root and replies as
    /// separate `MessageRowView`s; this method handles both.
    func toggleDig(on message: Message) async {
        let id = message.id
        guard !pendingDigOperations.contains(id) else { return }
        pendingDigOperations.insert(id)
        defer { pendingDigOperations.remove(id) }

        let originalCopy = currentCopy(of: id) ?? message
        let optimistic = originalCopy.byTogglingDig()
        replace(id: id, with: optimistic)

        do {
            let confirmed = try await (
                originalCopy.didDig
                    ? messages.undig(messageId: id)
                    : messages.dig(messageId: id)
            )
            replace(id: id, with: confirmed)
            error = nil
        } catch {
            // Roll back.
            replace(id: id, with: originalCopy)
            self.error = error
        }
    }

    // MARK: - M2 — Delete root message

    /// Deletes the loaded root message. The view confirms via a
    /// `.confirmationDialog` before calling. On success sets
    /// `didDeleteRoot`; the view dismisses itself off that flag.
    func deleteCurrentMessage() async {
        do {
            try await messages.delete(messageId: messageID)
            didDeleteRoot = true
            error = nil
        } catch {
            self.error = error
        }
    }

    // MARK: - M2 — Composer event bus consumption

    /// Applies an event posted by the composer / repost sheet / inline
    /// reply elsewhere. Pure local mutation — no networking.
    func apply(event: ComposerEvent) {
        switch event {
        case .replyCreated(let parentID, let reply):
            guard parentID == messageID else { return }
            if !replies.contains(where: { $0.id == reply.id }) {
                replies.append(reply)
            }
        case .messageUpdated(let updated):
            if updated.id == messageID {
                message = updated
            } else if let index = replies.firstIndex(where: { $0.id == updated.id }) {
                replies[index] = updated
            }
        case .messageDeleted(let id):
            if id == messageID {
                didDeleteRoot = true
            } else {
                replies.removeAll { $0.id == id }
            }
        case .messageCreated, .messageReposted:
            // Top-level posts are the Timeline's concern.
            break
        }
    }

    /// Ownership check used by the view to gate Edit / Delete on the
    /// message header or any reply row. `nil` `currentUserID` always
    /// returns `false` so the menu items hide rather than show
    /// enabled-but-broken.
    func canEdit(_ message: Message, currentUserID: String?) -> Bool {
        guard let currentUserID else { return false }
        return message.author.id == currentUserID
    }

    // MARK: - Internals

    private func currentCopy(of id: String) -> Message? {
        if message?.id == id { return message }
        return replies.first(where: { $0.id == id })
    }

    private func replace(id: String, with newCopy: Message) {
        if message?.id == id {
            message = newCopy
            return
        }
        if let index = replies.firstIndex(where: { $0.id == id }) {
            replies[index] = newCopy
        }
    }
}

// MARK: - Optimistic dig helper

private extension Message {
    /// Returns a copy with the dig state flipped (boolean toggled and
    /// the count nudged ±1). Used by `toggleDig` to apply the
    /// optimistic local change before the round-trip resolves.
    func byTogglingDig() -> Message {
        let newDidDig = !didDig
        let delta = newDidDig ? 1 : -1
        return Message(
            id: id,
            author: author,
            text: text,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: tags,
            visibility: visibility,
            digCount: max(0, digCount + delta),
            didDig: newDidDig,
            repostCount: repostCount,
            replyCount: replyCount,
            parentID: parentID,
            repost: repost,
            scheduledAt: scheduledAt
        )
    }
}
