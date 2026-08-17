// SearchViewModel
//
// Drives `SearchRootView`: the global search surface (work-consolidation.md G5).
// Owns the debounced query string, the grouped `SearchResults`, and the
// loading / error state. Reads through `SearchServicing` only — no direct
// API access — so unit tests substitute a stub service.
//
// Debounce: every keystroke re-binds `query`; `search()` cancels the
// in-flight fetch and schedules a fresh one `debounce` after the most
// recent keystroke (mirrors `DocumentEditorViewModel`'s injectable
// `ContinuousClock`-driven debounce so tests run with `.zero`). A blank /
// whitespace-only query clears the results synchronously and never fans
// out a request — the domain `SearchServicing.all(query:)` short-circuits
// too, but clearing locally keeps the UI honest without a round-trip.
//
// A monotonically-increasing `generation` token guards against a slow
// early request landing after a faster later one — a stale response is
// dropped rather than clobbering fresher results.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class SearchViewModel {

    // MARK: - Configuration

    /// Debounce window applied to the query field. Matches the keystroke
    /// cadence of the composer / editor so the global search feels the
    /// same. Tests pass `.zero` for immediate resolution.
    static let searchDebounce: Duration = .milliseconds(300)

    /// Page size handed to the search service for each resource.
    static let pageSize: Int = 20

    // MARK: - Dependencies

    private let service: SearchServicing
    private let debounce: Duration

    // MARK: - Observable state

    /// The bound query string. Setting it (re)schedules a debounced
    /// search; the view binds a `TextField` to it directly.
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    /// The grouped hits from the most recent successful search. Cleared
    /// when the query is blanked.
    private(set) var results: SearchResults = .empty

    /// True while a search round-trip is in flight.
    private(set) var isSearching: Bool = false

    /// Surfaced error from the most recent failed search. Cleared on the
    /// next successful round-trip or when the query is blanked.
    private(set) var error: Error?

    /// True once a search for a non-blank query has resolved (success or
    /// failure). Lets the view distinguish "type something" from "no
    /// results for this term".
    private(set) var hasSearched: Bool = false

    // MARK: - Internals

    /// Owns the debounced search task so a fresh keystroke cancels the
    /// pending fetch. `[weak self]` capture; no `deinit`-time cancel
    /// needed (Observation-macro semantics — mirrors `CurrentUserStore`).
    private var pendingSearchTask: Task<Void, Never>?

    /// Monotonic token: only the newest issued search may write results.
    private var generation: Int = 0

    // MARK: - Init

    init(service: SearchServicing, debounce: Duration = searchDebounce) {
        self.service = service
        self.debounce = debounce
    }

    // MARK: - Intents

    /// Runs the current query immediately, bypassing the debounce. Bound
    /// to the search field's `onSubmit` so pressing return doesn't wait
    /// out the debounce window.
    func searchNow() async {
        pendingSearchTask?.cancel()
        await performSearch()
    }

    /// Clears the query, results, and error in one shot. Bound to the
    /// field's clear button.
    func clear() {
        pendingSearchTask?.cancel()
        query = ""
        results = .empty
        error = nil
        hasSearched = false
        isSearching = false
    }

    // MARK: - Debounce

    private func scheduleSearch() {
        pendingSearchTask?.cancel()
        // Blank query: clear synchronously, no request. `SearchServicing`
        // short-circuits a blank term too, but clearing locally keeps the
        // rendered state consistent the instant the field empties.
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = .empty
            error = nil
            hasSearched = false
            isSearching = false
            return
        }
        let interval = debounce
        pendingSearchTask = Task { [weak self] in
            if interval > .zero {
                try? await Task.sleep(for: interval)
            }
            guard let self, !Task.isCancelled else { return }
            await self.performSearch()
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank term at fire time (e.g. the user deleted everything
        // during the debounce) clears rather than searching.
        guard !trimmed.isEmpty else {
            results = .empty
            error = nil
            hasSearched = false
            isSearching = false
            return
        }
        generation += 1
        let issued = generation
        isSearching = true
        do {
            let hits = try await service.all(query: trimmed, limit: Self.pageSize)
            // Drop a stale response — a newer search superseded this one.
            guard issued == generation else { return }
            results = hits
            error = nil
            hasSearched = true
            isSearching = false
        } catch {
            guard issued == generation else { return }
            self.error = error
            results = .empty
            hasSearched = true
            isSearching = false
        }
    }
}
