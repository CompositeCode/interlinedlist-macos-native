// DirectMessagesListViewModel
//
// Drives the conversation-list column of `DirectMessagesRootView`
// (work-consolidation.md G1, G22). Owns the selected folder (Inbox / Sent
// / Deleted), the conversation rows, pagination, the unread badge count,
// and the trash / restore actions. Reads through `DirectMessagesServicing`
// only — no direct API access — so unit tests substitute a stub service.
//
// Two sources, one rendered list (G22):
//
//   • Inbox → `conversations(cursor:)`, the server-grouped feed. One row
//     per conversation keyed by `pairKey`, newest first, with its own
//     cursor. No client-side grouping is involved, so a conversation whose
//     newest message would have fallen off the end of a folder page still
//     appears — the failure mode the old inbox had.
//   • Sent / Deleted → `folder(_:cursor:)`, still a flat newest-first list
//     of `DirectMessage`s folded into one `DMConversation` per other
//     participant. The conversations route does not replace these: it is
//     the inbox, not a folder listing.
//
// Client-side grouping needs the current user id (to know which side of a
// message is "other"); it comes from the injected `currentUserID` closure
// so the view model always sees the latest session (mirrors
// `ProfileViewModel`).
//
// Optimistic trash / restore (per the swift-engineer skill): snapshot the
// active source — the flat message list on the folder path, the summary
// list on the inbox path — mutate locally, call the service, and on
// failure restore the snapshot and surface the error. A
// `pendingOperations` set keyed by message id debounces rapid re-taps.
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
    ///
    /// Optional because the server-grouped row's populated shape is
    /// unverified (see `DMConversationDTO`): a row whose message we could
    /// not decode still lists as a conversation rather than vanishing.
    /// Always non-nil on the client-grouped Sent / Deleted path.
    let latestMessage: DirectMessage?
    /// Count of inbound (received, unread) messages in this conversation.
    let unreadCount: Int
    /// All messages in the conversation from this folder page, newest-first.
    /// Empty on the server-grouped inbox path, which reports only the newest.
    let messages: [DirectMessage]

    /// One-line row preview.
    var preview: String { latestMessage?.body ?? "" }
}

@MainActor
@Observable
final class DirectMessagesListViewModel {

    // MARK: - Dependencies

    private let service: DirectMessagesServicing
    private let bus: DirectMessagesEventBus?
    private let currentUserIDProvider: @MainActor () -> String?

    // MARK: - Observable state

    /// The folder whose listing is shown. Changing it triggers a reload and
    /// switches the backing source (Inbox → conversations, Sent / Deleted →
    /// folder listing).
    var folder: DMFolder {
        didSet {
            guard folder != oldValue else { return }
            Task { await load() }
        }
    }

    /// Whether the current folder reads the server-grouped conversations
    /// feed. Only the Inbox does; the route is the inbox, not a folder.
    private var usesConversationsFeed: Bool { folder == .inbox }

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

    /// The flat, newest-first message list backing `conversations` on the
    /// Sent / Deleted path. Kept so trash/restore can mutate the source and
    /// re-group. Empty while the Inbox is shown.
    private var messages: [DirectMessage] = []

    /// The server-grouped rows backing `conversations` on the Inbox path.
    /// Empty while Sent / Deleted is shown.
    private var summaries: [DMConversationSummary] = []

    // MARK: - Init

    init(
        service: DirectMessagesServicing,
        eventBus: DirectMessagesEventBus? = nil,
        currentUserID: @MainActor @escaping () -> String? = { nil },
        initialFolder: DMFolder = .inbox
    ) {
        self.service = service
        self.bus = eventBus
        self.currentUserIDProvider = currentUserID
        // Assigned in the initializer, so the `didSet` reload does not fire —
        // the caller owns the first `load()`. Lets a test start on Sent /
        // Deleted without racing an unawaited reload task.
        self.folder = initialFolder
    }

    // MARK: - Intents

    /// First-time load + pull-to-refresh for the current folder. Replaces
    /// the rendered list and refreshes the unread count.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if usesConversationsFeed {
                let page = try await service.conversations(cursor: nil)
                summaries = page.conversations
                messages = []
                nextCursor = page.nextCursor
            } else {
                let page = try await service.folder(folder, cursor: nil)
                messages = page.messages
                summaries = []
                nextCursor = page.nextCursor
            }
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
            if usesConversationsFeed {
                let page = try await service.conversations(cursor: cursor)
                summaries.append(contentsOf: page.conversations)
                nextCursor = page.nextCursor
            } else {
                let page = try await service.folder(folder, cursor: cursor)
                messages.append(contentsOf: page.messages)
                nextCursor = page.nextCursor
            }
            regroup()
            error = nil
        } catch is CancellationError {
            // Cancelled pagination — not a failure; leave the list as-is.
        } catch {
            self.error = error
        }
    }

    /// Resolves a bare DM id to the username of the conversation it belongs
    /// to, so a deep link that names a *message* can open the right *thread*
    /// (work-consolidation.md G22 — `GET /api/dm/{id}`).
    ///
    /// Answers from the loaded listing first and only calls the API for an id
    /// the listing doesn't already hold — a deep link arriving while the
    /// inbox is on screen shouldn't cost a round-trip.
    ///
    /// Returns `nil` when the message is unknown, is not readable by this
    /// account, or names no resolvable participant; the caller leaves the
    /// selection alone rather than opening an empty thread.
    func conversationUsername(forMessageID id: String) async -> String? {
        if let known = knownConversationUsername(forMessageID: id) { return known }
        do {
            return username(of: try await service.message(id: id))
        } catch {
            // A deep link to a message we can't read is not a listing
            // failure — don't blank the list with an error banner over it.
            return nil
        }
    }

    /// The conversation username for `id` if the loaded listing already knows
    /// the message, else `nil`.
    private func knownConversationUsername(forMessageID id: String) -> String? {
        if let summary = summaries.first(where: { $0.latestMessage?.id == id }) {
            let name = summary.otherUsername
            return name.isEmpty ? nil : name
        }
        if let message = messages.first(where: { $0.id == id }) {
            return username(of: message)
        }
        return nil
    }

    /// The other participant's username on a message, given the current user.
    /// Without a resolved current user we fall back to the sender, which is
    /// the correct side for the common inbound-deep-link case.
    private func username(of message: DirectMessage) -> String? {
        let me = currentUserIDProvider()
        let name: String?
        if let me, message.senderId == me {
            name = message.recipient?.username
        } else {
            name = message.sender?.username ?? message.recipient?.username
        }
        guard let name, !name.isEmpty else { return nil }
        return name
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
        await mutate(messageID: messageID) { [service] in
            try await service.trash(id: messageID)
        }
    }

    /// Restores a message out of the Deleted folder. Optimistic in the
    /// same shape as `trash`.
    func restore(messageID: String) async {
        await mutate(messageID: messageID) { [service] in
            try await service.restore(id: messageID)
        }
    }

    /// The shared optimistic body behind `trash` / `restore`.
    ///
    /// Snapshots whichever source is active — the flat message list on the
    /// Sent / Deleted path, the summary list on the Inbox path — removes the
    /// affected row, runs `action`, and restores the snapshot on failure.
    /// Rejects an id that is not in the current listing *before* the service
    /// is touched, so a stale row can't fire a doomed request.
    private func mutate(
        messageID: String,
        action: @escaping () async throws -> Void
    ) async {
        guard !pendingOperations.contains(messageID) else { return }
        guard knowsMessage(id: messageID) else { return }
        pendingOperations.insert(messageID)
        defer { pendingOperations.remove(messageID) }

        let messageSnapshot = messages
        let summarySnapshot = summaries
        messages.removeAll { $0.id == messageID }
        summaries.removeAll { $0.latestMessage?.id == messageID }
        regroup()
        do {
            try await action()
            error = nil
            await refreshUnreadCount()
        } catch {
            messages = messageSnapshot
            summaries = summarySnapshot
            regroup()
            self.error = error
        }
    }

    /// Whether `id` names a message the current listing actually knows about,
    /// in either source.
    private func knowsMessage(id: String) -> Bool {
        messages.contains { $0.id == id } || summaries.contains { $0.latestMessage?.id == id }
    }

    /// Seeds the flat (folder-path) listing without going through the
    /// service. For tests and previews.
    func seedForTest(messages: [DirectMessage], nextCursor: String? = nil, unreadCount: Int = 0) {
        self.messages = messages
        self.summaries = []
        self.nextCursor = nextCursor
        self.unreadCount = unreadCount
        self.hasLoadedOnce = true
        regroup()
    }

    /// Seeds the server-grouped (Inbox-path) listing without going through
    /// the service. For tests and previews.
    func seedForTest(
        conversations: [DMConversationSummary],
        nextCursor: String? = nil,
        unreadCount: Int = 0
    ) {
        self.summaries = conversations
        self.messages = []
        self.nextCursor = nextCursor
        self.unreadCount = unreadCount
        self.hasLoadedOnce = true
        regroup()
    }

    // MARK: - Grouping

    /// Rebuilds `conversations` from whichever source is active.
    ///
    /// On the Inbox path the server already did the grouping, so this is a
    /// straight projection of `summaries` — no folding, no dependence on how
    /// much of the listing we happen to have fetched. On Sent / Deleted it
    /// folds the flat message list as before.
    private func regroup() {
        guard !usesConversationsFeed else {
            conversations = summaries.map(Self.row(from:))
            return
        }
        regroupFolderListing()
    }

    /// Projects one server-grouped summary into a rendered row. The server
    /// owns identity, the other participant, and the unread count; nothing
    /// here re-derives them from message contents.
    private static func row(from summary: DMConversationSummary) -> DMConversation {
        DMConversation(
            id: summary.id,
            otherUser: summary.otherUser,
            otherUsername: summary.otherUsername,
            latestMessage: summary.latestMessage,
            unreadCount: summary.unreadCount,
            // The conversations feed reports only the newest message per
            // conversation; the full back-and-forth comes from the thread.
            messages: summary.latestMessage.map { [$0] } ?? []
        )
    }

    /// Folds the flat message list into one conversation per other-user,
    /// newest-first. Stable: ties keep the newest message's timestamp.
    /// Sent / Deleted only — the Inbox is grouped server-side.
    private func regroupFolderListing() {
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
