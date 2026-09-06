// TrendingTagsViewModel
//
// Drives the timeline's trending-tags strip (work-consolidation.md G20).
//
// Kept separate from `TimelineViewModel` so the timeline's load path and its
// signature are untouched: this only feeds a presentational strip whose taps
// call the timeline's existing `setTagFilter`.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class TrendingTagsViewModel {

    private let service: TagsServicing?
    private let limit: Int

    private(set) var tags: [TrendingTag] = []
    private(set) var isLoading = false

    /// Whether the strip has anything to render. The timeline hides the strip
    /// entirely when false, so an unavailable or empty trending list costs no
    /// vertical space.
    var isVisible: Bool { !tags.isEmpty }

    init(service: TagsServicing?, limit: Int = 12) {
        self.service = service
        self.limit = limit
    }

    func load() async {
        guard let service, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            tags = try await service.trending(limit: limit)
        } catch {
            // A trending strip is ambient decoration over the real feed — a
            // failure hides it rather than pushing an error the user did not ask
            // for in front of their timeline.
            tags = []
        }
    }
}
