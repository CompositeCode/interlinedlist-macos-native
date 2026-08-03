// ScheduledPostsViewModel
//
// Drives `ScheduledPostsRootView`: the list of the caller's pending
// scheduled posts (PLAN.md §1 "Scheduled posts", §5 "Scheduled sidebar
// section", §6 M6). Reads through `MessagesServicing.scheduledPosts()` —
// no direct API access — so unit tests substitute a stub service.
//
// NW-3: cancel and reschedule are now supported. Both use the optimistic-UI
// pattern (snapshot → mutate locally → service call → on success replace
// with server copy; on failure restore snapshot). The row context menu
// surfaces both actions; `actionError` captures the last mutation failure
// without replacing the loaded list.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ScheduledPostsViewModel {

    // MARK: - Dependencies

    private let messages: MessagesServicing

    // MARK: - Observable state

    /// The pending scheduled posts, as the server returns them. Each carries
    /// a non-nil `scheduledAt`.
    private(set) var posts: [Message] = []

    /// True while a load is in flight.
    private(set) var isLoading: Bool = false

    /// True while a background revalidation runs *after* the cache has
    /// already painted the list (stale-while-revalidate, PLAN.md §5).
    /// Non-blocking: the view shows a subtle indicator instead of the
    /// full-screen loading state.
    private(set) var isRefreshing: Bool = false

    /// True when a background revalidation failed while cached posts were on
    /// screen. The list keeps its cached rows; the view surfaces this as an
    /// unobtrusive hint rather than blanking the list.
    private(set) var refreshFailed: Bool = false

    /// Surfaced error from the most recent failed load. Cleared on the next
    /// successful round-trip.
    private(set) var error: Error?

    /// True once the first load has resolved (success or failure). Lets the
    /// view distinguish "first-render shimmer" from "loaded but empty".
    private(set) var hasLoadedOnce: Bool = false

    /// Error from the last cancel or reschedule action. Distinct from `error`
    /// so a failed mutation doesn't blank the loaded list.
    private(set) var actionError: Error?

    /// Timestamp of the last successful network refresh — drives the TTL.
    private(set) var lastRefreshedAt: Date?

    /// Freshness window: a re-appearing view whose posts refreshed within
    /// this many seconds skips revalidation and trusts cache.
    static let refreshTTL: TimeInterval = 45

    /// Whether a `.task`-driven re-appearance should revalidate.
    var shouldRefresh: Bool {
        guard let lastRefreshedAt else { return true }
        return Date().timeIntervalSince(lastRefreshedAt) >= Self.refreshTTL
    }

    // MARK: - Init

    init(messages: MessagesServicing) {
        self.messages = messages
    }

    // MARK: - Intents

    /// First-time + refresh load, stale-while-revalidate (PLAN.md §5): on a
    /// cold start it paints the cached posts immediately (suppressing the
    /// full-screen loading state) and then revalidates over the network. A
    /// manual refresh (the list is already loaded) revalidates in place. On
    /// a network failure the prior list is left intact — `error` is set only
    /// on a cold-cache failure so the view can show a retry affordance;
    /// `refreshFailed` is set (non-blocking) when cached rows are on screen.
    func load() async {
        guard !isLoading, !isRefreshing else { return }
        // Paint from cache only on the very first load; a manual refresh keeps
        // whatever is already rendered.
        let cachePainted: Bool
        if !hasLoadedOnce {
            let cached = await messages.cachedScheduledPosts()
            if !cached.isEmpty {
                posts = cached
                hasLoadedOnce = true
                cachePainted = true
            } else {
                cachePainted = false
            }
        } else {
            cachePainted = !posts.isEmpty
        }

        if cachePainted {
            isRefreshing = true
        } else {
            isLoading = true
        }
        refreshFailed = false
        defer {
            isLoading = false
            isRefreshing = false
        }
        do {
            let loaded = try await messages.scheduledPosts()
            posts = loaded
            error = nil
            hasLoadedOnce = true
            lastRefreshedAt = Date()
        } catch {
            if cachePainted {
                refreshFailed = true
            } else {
                self.error = error
            }
            hasLoadedOnce = true
        }
    }

    /// Convenience for tests + previews — seed the rendered list without going
    /// through the service.
    func seedForTest(posts: [Message]) {
        self.posts = posts
        self.hasLoadedOnce = true
    }

    // MARK: - NW-3: Cancel and reschedule

    /// Cancels a scheduled post. Optimistically removes it from the list,
    /// calls the service, and on failure restores the snapshot.
    func cancel(post: Message) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let snapshot = posts
        posts.remove(at: index)
        actionError = nil
        do {
            try await messages.cancelScheduled(messageId: post.id)
        } catch {
            posts = snapshot
            actionError = error
        }
    }

    /// Reschedules a post to a new date. Optimistically updates the row's
    /// `scheduledAt`, calls the service, then on success replaces the
    /// optimistic copy with the server's authoritative value. On failure,
    /// restores the snapshot.
    func reschedule(post: Message, to newDate: Date) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let snapshot = posts
        let optimistic = Message(
            id: post.id,
            author: post.author,
            text: post.text,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
            tags: post.tags,
            visibility: post.visibility,
            digCount: post.digCount,
            didDig: post.didDig,
            repostCount: post.repostCount,
            replyCount: post.replyCount,
            parentID: post.parentID,
            repost: post.repost,
            scheduledAt: newDate
        )
        posts[index] = optimistic
        actionError = nil
        do {
            let confirmed = try await messages.reschedule(messageId: post.id, newDate: newDate)
            if let currentIdx = posts.firstIndex(where: { $0.id == post.id }) {
                posts[currentIdx] = confirmed
            }
        } catch {
            posts = snapshot
            actionError = error
        }
    }
}
