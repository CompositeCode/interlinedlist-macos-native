// DirectMessagesListViewModel
//
// Drives the conversation-list column of `DirectMessagesRootView` (the-
// gaps.md G1). Owns the selected folder (Inbox / Sent / Deleted), the
// folder listing collapsed into per-conversation rows, pagination via
// the `DMPage.nextCursor`, the unread badge count, and the trash /
// restore actions. Reads through `DirectMessagesServicing` only — no
// direct API access — so unit tests substitute a stub service.
//
// Conversation grouping: the folder listing is a flat, newest-first list
// of `DirectMessage`s. A conversation is "the other participant" — the
// non-current user on each message. We fold the flat list into one
// `DMConversation` per other-user, keeping the newest message as the
// preview and counting unread inbound messages. Grouping needs the
// current user id (to know which side is "other"); it comes from the
// injected `currentUserID` closure so the view model always sees the
// latest session (mirrors `ProfileViewModel`).
//
// Optimistic trash / restore (per the swift-engineer skill): snapshot the
// affected messages, mutate locally, call the service, and on failure
// restore the snapshot and surface the error. A `pendingOperations` set
// keyed by message id debounces rapid re-taps.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

// MARK: - DMConversation

/// One collapsed conversation row: the other participant, the newest
/// message as a preview, and the count of unread inbound messages.
struct DMConversation: Identifiable, Equatable, Sendable {
    /// Stable identity — the other participant's user id when known, else
    /// their username, else the newest message id. Never empty.
    let id: String
    /// The other participant (nil-safe display handled by the view).
    let otherUser: UserSummary?
    /// A stable username used to open the thread. Falls back through the
    /// other user's username; empty only in the degenerate no-user case.
    let otherUsername: String
    /// The newest message in the conversation, rendered as the preview.
    let latestMessage: DirectMessage
    /// Count of inbound (received, unread) messages in this conversation.
    let unreadCount: Int
    /// All messages in the conversation from this folder page, newest-first.
    let messages: [DirectMessage]
}

@MainActor
@Observable
final class DirectMessagesListViewModel {

    // MARK: - Dependencies

    private let service: DirectMessagesServicing
    private let bus: DirectMessagesEventBus?
    private let currentUserIDProvider: @MainActor () -> String?

    // MARK: - Observable state

    /// The folder whose listing is shown. Changing it triggers a reload.
    var folder: DMFolder = .inbox {
        didSet {
            guard folder != oldValue else { return }
            Task { await load() }
        }
    }

    /// The collapsed conversation rows for the current folder, newest-first.
    private(set) var conversations: [DMConversation] = []

    /// Server-authoritative unread count from `unreadCount()`. Drives the
    /// sidebar pip / dock badge (via the bus).
    private(set) var unreadCount: Int = 0

    /// Cursor for the next page, or `nil` when the listing is exhausted.
    private(set) var nextCursor: String?

    /// True when another page can be loaded.
    var hasMore: Bool { nextCursor != nil }

    /// True while a full (re)load is in flight.
    private(set) var isLoading: Bool = false

    /// True while a next-page fetch is in flight.
    private(set) var isLoadingMore: Bool = false

    /// Surfaced error from the most recent failed load / action.
    private(set) var error: Error?

    /// True once the first load resolved (success or failure). Lets the
    /// view distinguish first-render shimmer from a genuinely empty folder.
    private(set) var hasLoadedOnce: Bool = false

    /// Per-message debounce set so rapid trash/restore re-taps on the
    /// same message don't double-fire the service.
    private var pendingOperations: Set<String> = []

    /// The flat, newest-first message list backing `conversations`. Kept
    /// so trash/restore can mutate the source and re-group.
    private var messages: [DirectMessage] = []

    // MARK: - Init

    init(
        service: DirectMessagesServicing,
        eventBus: DirectMessagesEventBus? = nil,
        currentUserID: @MainActor @escaping () -> String? = { nil }
    ) {
        self.service = service
        self.bus = eventBus
        self.currentUserIDProvider = currentUserID
    }

    // MARK: - Intents

    /// First-time load + pull-to-refresh for the current folder. Replaces
    /// the rendered list and refreshes the unread count.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await service.folder(folder, cursor: nil)
            messages = page.messages
            nextCursor = page.nextCursor
            regroup()
            error = nil
            hasLoadedOnce = true
        } catch is CancellationError {
            // Cancelled (view teardown / folder switch superseded), not
            // failed. Leave state untouched so no spurious error banner shows.
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
        // Refresh the unread badge alongside the listing. A failed unread
        // read is soft — the listing is the load-bearing data.
        await refreshUnreadCount()
    }

    /// Appends the next page when the user scrolls to the end. No-op when
    /// there is no next cursor or a page fetch is already in flight.
    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.folder(folder, cursor: cursor)
            messages.append(contentsOf: page.messages)
            nextCursor = page.nextCursor
            regroup()
            error = nil
        } catch is CancellationError {
            // Cancelled pagination — not a failure; leave the list as-is.
        } catch {
            self.error = error
        }
    }

    /// Re-reads the server unread count and publishes it on the bus so the
    /// dock badge / sidebar pip update. Soft-fails: a failed read leaves
    /// the prior count in place and does not surface an error.
    func refreshUnreadCount() async {
        do {
            let count = try await service.unreadCount()
            unreadCount = count
            bus?.post(.unreadCountChanged(count))
        } catch {
            // Soft — keep the prior count.
        }
    }

    /// Moves a message to the Deleted folder (from Inbox / Sent).
    /// Optimistic: drop it from the local listing, call `trash`, and on
    /// failure restore the snapshot and surface the error.
    func trash(messageID: String) async {
        guard !pendingOperations.contains(messageID) else { return }
        guard messages.contains(where: { $0.id == messageID }) else { return }
        pendingOperations.insert(messageID)
        defer { pendingOperations.remove(messageID) }

        let snapshot = messages
        messages.removeAll { $0.id == messageID }
        regroup()
        do {
            try await service.trash(id: messageID)
            error = nil
            await refreshUnreadCount()
        } catch {
            messages = snapshot
            regroup()
            self.error = error
        }
    }

    /// Restores a message out of the Deleted folder. Optimistic in the
    /// same shape as `trash`.
    func restore(messageID: String) async {
        guard !pendingOperations.contains(messageID) else { return }
        guard messages.contains(where: { $0.id == messageID }) else { return }
        pendingOperations.insert(messageID)
        defer { pendingOperations.remove(messageID) }

        let snapshot = messages
        messages.removeAll { $0.id == messageID }
        regroup()
        do {
            try await service.restore(id: messageID)
            error = nil
            await refreshUnreadCount()
        } catch {
            messages = snapshot
            regroup()
            self.error = error
        }
    }

    /// Seeds the flat listing without going through the service. For tests
    /// and previews.
    func seedForTest(messages: [DirectMessage], nextCursor: String? = nil, unreadCount: Int = 0) {
        self.messages = messages
        self.nextCursor = nextCursor
        self.unreadCount = unreadCount
        self.hasLoadedOnce = true
        regroup()
    }

    // MARK: - Grouping

    /// Folds the flat message list into one conversation per other-user,
    /// newest-first. Stable: ties keep the newest message's timestamp.
    private func regroup() {
        let me = currentUserIDProvider()
        var order: [String] = []
        var buckets: [String: [DirectMessage]] = [:]

        for message in messages {
            let key = conversationKey(for: message, me: me)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(message)
        }

        conversations = order.compactMap { key -> DMConversation? in
            guard let bucket = buckets[key], let latest = bucket.first else { return nil }
            let other = otherUser(in: latest, me: me)
            let username = other?.username ?? key
            let unread = bucket.filter { isUnreadInbound($0, me: me) }.count
            return DMConversation(
                id: key,
                otherUser: other,
                otherUsername: username,
                latestMessage: latest,
                unreadCount: unread,
                messages: bucket
            )
        }
    }

    /// The other participant on a message, given the current user id.
    /// Without a resolved current user we cannot tell which side is
    /// "other", so we fall back to the recipient (the common inbox case).
    private func otherUser(in message: DirectMessage, me: String?) -> UserSummary? {
        guard let me else { return message.sender ?? message.recipient }
        return message.senderId == me ? message.recipient : message.sender
    }

    /// A stable grouping key: the other participant's id when derivable,
    /// else their username, else the message id (degenerate).
    private func conversationKey(for message: DirectMessage, me: String?) -> String {
        if let me {
            let otherId = message.senderId == me ? message.recipientId : message.senderId
            if !otherId.isEmpty { return otherId }
        }
        if let username = otherUser(in: message, me: me)?.username, !username.isEmpty {
            return username
        }
        return message.id
    }

    /// A message counts toward unread when it was received (not sent by
    /// me) and has not been read. Without a resolved current user we
    /// treat unread-and-not-outgoing conservatively as inbound.
    private func isUnreadInbound(_ message: DirectMessage, me: String?) -> Bool {
        guard !message.isRead else { return false }
        guard let me else { return true }
        return message.recipientId == me
    }
}
