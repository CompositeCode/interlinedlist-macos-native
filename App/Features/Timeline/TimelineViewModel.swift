// TimelineViewModel
//
// Drives `TimelineRootView`: owns the current scope / tag filter, the
// loaded pages, and the loading & error state. Reads through
// `MessagesServicing` only — no direct API or cache access — so unit
// tests substitute a stub service trivially (PLAN.md §3, §7).
//
// Initial loads consume `timelineStream(...)` so the cached page
// renders instantly and the fresh page replaces it in place
// (stale-while-revalidate per PLAN.md §5). Subsequent pages use the
// throwing `timeline(...)` call and append.
//
// M2 surface:
// - `toggleDig(message:)` with optimistic local mutation + rollback
//   on failure (PLAN.md §6 M2 "Dig / undig toggle").
// - `deleteMessage(id:)` for own-message delete via the row's context
//   menu; the view confirms first.
// - `apply(event:)` consumes the `ComposerEventBus` so a successful
//   create / repost / update / delete in the composer window mutates
//   the rendered list in place (no full refetch).

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class TimelineViewModel {

    // MARK: - Inputs / configuration

    /// Page size for both the initial load and infinite scroll. Mirrors
    /// the API's default `limit` so we always ask for full pages.
    static let pageSize: Int = 20

    private let messages: MessagesServicing

    // MARK: - Observable state

    /// Currently selected scope (All / Mine).
    private(set) var scope: TimelineScope
    /// Active tag filter, or `nil` for the unfiltered feed.
    private(set) var tagFilter: String?
    /// Pages loaded so far, in display order.
    private(set) var messagesLoaded: [Message] = []
    /// True while a network round-trip is in flight (initial, refresh,
    /// or load-more).
    private(set) var isLoading: Bool = false
    /// Surfaced error from the most recent failed load, dig, or delete.
    /// Cleared on the next successful round-trip.
    private(set) var error: Error?
    /// Whether the server reports more pages beyond what's loaded.
    private(set) var hasMore: Bool = false
    /// The `offset` to pass on the next `loadMore` call. `nil` when
    /// `hasMore` is false.
    private(set) var nextOffset: Int?

    /// Set of message IDs whose dig is currently in flight. Used to
    /// de-bounce rapid toggling so the optimistic flip doesn't double-
    /// fire and confuse the server count.
    private var pendingDigOperations: Set<String> = []

    // MARK: - Init

    init(messages: MessagesServicing, scope: TimelineScope = .all, tagFilter: String? = nil) {
        self.messages = messages
        self.scope = scope
        self.tagFilter = tagFilter
    }

    // MARK: - Intents

    /// First-time load for the current scope + tag. Consumes the
    /// stale-while-revalidate stream so the cached page renders
    /// immediately and is then replaced by the fresh page. Safe to
    /// call repeatedly; each call resets paging state and starts over.
    func initialLoad() async {
        await load(reset: true, useStream: true)
    }

    /// Re-fetches page zero in place (`.refreshable` handler). Skips
    /// the cache, so the user sees the live result.
    func refresh() async {
        await load(reset: true, useStream: false)
    }

    /// Appends the next page when one exists. No-op while a load is in
    /// flight or when `hasMore` is false — the view calls this on the
    /// trailing row's `.onAppear` and we de-dupe here rather than push
    /// the responsibility onto the view.
    func loadMore() async {
        guard !isLoading, hasMore, let offset = nextOffset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await messages.timeline(
                scope: scope,
                tag: tagFilter,
                limit: Self.pageSize,
                offset: offset
            )
            messagesLoaded.append(contentsOf: page.messages)
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Switches scope and reloads from page zero. No-op when the scope
    /// is unchanged so toolbar bindings don't trigger spurious reloads.
    func changeScope(_ newScope: TimelineScope) async {
        guard newScope != scope else { return }
        scope = newScope
        await load(reset: true, useStream: true)
    }

    /// Sets (or clears) the tag filter and reloads from page zero. The
    /// filter is treated as a single string for M1; tag-token UI is M2+.
    func setTagFilter(_ tag: String?) async {
        let normalized = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (normalized?.isEmpty ?? true) ? nil : normalized
        guard resolved != tagFilter else { return }
        tagFilter = resolved
        await load(reset: true, useStream: true)
    }

    // MARK: - M2 — Dig / undig with optimistic UI

    /// Flips the dig state on `message` optimistically, then calls
    /// `dig` / `undig` to confirm. On failure rolls back to the
    /// pre-mutation copy and surfaces the error; on success replaces
    /// the optimistic copy with the service's authoritative return
    /// value (which carries the server-confirmed count).
    func toggleDig(on message: Message) async {
        let id = message.id
        guard !pendingDigOperations.contains(id) else { return }
        guard let originalIndex = messagesLoaded.firstIndex(where: { $0.id == id }) else { return }
        let original = messagesLoaded[originalIndex]
        let optimistic = original.byTogglingDig()
        pendingDigOperations.insert(id)
        defer { pendingDigOperations.remove(id) }

        // Optimistic flip — visible to the view immediately.
        messagesLoaded[originalIndex] = optimistic

        do {
            let confirmed = try await (
                original.didDig
                    ? messages.undig(messageId: id)
                    : messages.dig(messageId: id)
            )
            // The server may have settled on a different count than our
            // local ±1 (e.g. someone else dug in the same window).
            // Trust the service's return value over the optimistic copy.
            if let currentIndex = messagesLoaded.firstIndex(where: { $0.id == id }) {
                messagesLoaded[currentIndex] = confirmed
            }
            error = nil
        } catch {
            // Roll back the optimistic flip.
            if let rollbackIndex = messagesLoaded.firstIndex(where: { $0.id == id }) {
                messagesLoaded[rollbackIndex] = original
            }
            self.error = error
        }
    }

    // MARK: - M2 — Delete own message

    /// Deletes `id` and removes it from the rendered list. The view
    /// confirms via a `.confirmationDialog` before calling this; this
    /// method does not double-confirm.
    func deleteMessage(id: String) async {
        do {
            try await messages.delete(messageId: id)
            removeMessage(id: id)
            error = nil
        } catch {
            self.error = error
        }
    }

    // MARK: - M2 — Composer event bus consumption

    /// Applies a `ComposerEvent` to the rendered list. Pure local
    /// mutation — no networking. Called by the view when the bus
    /// yields a new event so the timeline reflects writes from the
    /// composer window / repost sheet / inline reply.
    func apply(event: ComposerEvent) {
        switch event {
        case .messageCreated(let message),
             .messageReposted(let message):
            // Prepend, unless we already have it (the user could have
            // refreshed between submit and event delivery).
            if !messagesLoaded.contains(where: { $0.id == message.id }) {
                messagesLoaded.insert(message, at: 0)
            }
        case .messageUpdated(let message):
            if let index = messagesLoaded.firstIndex(where: { $0.id == message.id }) {
                messagesLoaded[index] = message
            }
        case .messageDeleted(let id):
            removeMessage(id: id)
        case .replyCreated:
            // The timeline shows top-level messages; the reply belongs
            // on the detail screen, which has its own subscription.
            break
        }
    }

    /// Owner check used by the view to decide whether to show
    /// Edit / Delete on the row context menu. `nil` `currentUserID`
    /// (session not yet resolved) always returns `false` so the menu
    /// items stay hidden rather than show enabled-but-broken (PLAN.md
    /// §6 M2 rule).
    func canEdit(_ message: Message, currentUserID: String?) -> Bool {
        guard let currentUserID else { return false }
        return message.author.id == currentUserID
    }

    // MARK: - Internals

    private func removeMessage(id: String) {
        messagesLoaded.removeAll { $0.id == id }
    }

    private func load(reset: Bool, useStream: Bool) async {
        if reset {
            messagesLoaded = []
            hasMore = false
            nextOffset = nil
        }
        isLoading = true
        error = nil
        defer { isLoading = false }

        if useStream {
            do {
                for try await page in messages.timelineStream(
                    scope: scope,
                    tag: tagFilter,
                    limit: Self.pageSize,
                    offset: 0
                ) {
                    apply(page, reset: true)
                }
            } catch {
                self.error = error
            }
        } else {
            do {
                let page = try await messages.timeline(
                    scope: scope,
                    tag: tagFilter,
                    limit: Self.pageSize,
                    offset: 0
                )
                apply(page, reset: true)
            } catch {
                self.error = error
            }
        }
    }

    private func apply(_ page: TimelinePage, reset: Bool) {
        if reset {
            messagesLoaded = page.messages
        } else {
            messagesLoaded.append(contentsOf: page.messages)
        }
        hasMore = page.hasMore
        nextOffset = page.nextOffset
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
