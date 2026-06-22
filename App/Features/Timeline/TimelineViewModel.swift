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
    /// Surfaced error from the most recent failed load. Cleared on the
    /// next successful round-trip.
    private(set) var error: Error?
    /// Whether the server reports more pages beyond what's loaded.
    private(set) var hasMore: Bool = false
    /// The `offset` to pass on the next `loadMore` call. `nil` when
    /// `hasMore` is false.
    private(set) var nextOffset: Int?

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

    // MARK: - Internals

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
