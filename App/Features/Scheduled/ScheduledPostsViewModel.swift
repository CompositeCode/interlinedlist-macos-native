// ScheduledPostsViewModel
//
// Drives `ScheduledPostsRootView`: the read-only list of the caller's
// pending scheduled posts (PLAN.md §1 "Scheduled posts", §5 "Scheduled
// sidebar section", §6 M6). Reads through `MessagesServicing.scheduledPosts()`
// only — no direct API access — so unit tests substitute a stub service.
//
// v1 is intentionally read-only. The API exposes no cancel / reschedule
// endpoint (backend ask P3.3), so the list shows what is queued and links
// the user to the composer for creating new scheduled posts; rows carry no
// delete / edit affordance. When P3.3 lands, the row gains a destructive
// action and this view model grows an optimistic-removal path.
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

    /// Surfaced error from the most recent failed load. Cleared on the next
    /// successful round-trip.
    private(set) var error: Error?

    /// True once the first load has resolved (success or failure). Lets the
    /// view distinguish "first-render shimmer" from "loaded but empty".
    private(set) var hasLoadedOnce: Bool = false

    // MARK: - Init

    init(messages: MessagesServicing) {
        self.messages = messages
    }

    // MARK: - Intents

    /// First-time + refresh load. Replaces the rendered list with the server
    /// payload. On failure the prior list is left intact and `error` is set so
    /// the view can show a retry affordance without losing what it had.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await messages.scheduledPosts()
            posts = loaded
            error = nil
            hasLoadedOnce = true
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
    }

    /// Convenience for tests + previews — seed the rendered list without going
    /// through the service.
    func seedForTest(posts: [Message]) {
        self.posts = posts
        self.hasLoadedOnce = true
    }
}
