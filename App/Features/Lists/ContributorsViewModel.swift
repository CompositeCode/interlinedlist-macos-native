// ContributorsViewModel
//
// Drives `ContributorsView` — the ranked "who built this list" panel behind
// `GET /api/lists/{id}/contributors` (work-consolidation.md G23 / issue #48).
//
// The route is documented as unpaged ("no server paging") and returns the
// contributors already ranked, so this view model deliberately does no
// sorting of its own: the server owns the ranking formula and a future change
// to it should not need a client release.
//
// Reads through `ListsServicing` only. Per decision 0003 it consumes only
// `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ContributorsViewModel {

    private let lists: ListsServicing
    let listId: String

    /// Contributors in the server's ranking order.
    private(set) var contributors: [ListContributor] = []

    /// True while the load round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load.
    private(set) var error: Error?

    /// True once the first load resolved, so the view can tell "loading" from
    /// "nobody has contributed yet".
    private(set) var hasLoadedOnce: Bool = false

    init(lists: ListsServicing, listId: String) {
        self.lists = lists
        self.listId = listId
    }

    /// Total edits across everyone — the denominator the rows show their
    /// share against. `0` when the list has no contributors, which the view
    /// guards on before dividing.
    var totalScore: Int {
        contributors.reduce(0) { $0 + $1.score }
    }

    func load() async {
        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            contributors = try await lists.contributors(of: listId)
        } catch {
            self.error = error
        }
    }
}
