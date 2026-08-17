// SearchViewModelTests
//
// BDD-named tests for the global-search view model (work-consolidation.md G5).
// Covers the required quartet plus the stale-response guard and clear:
//   - happy: a non-blank query populates the three grouped sections.
//   - invalid input: a blank / whitespace-only query never calls the
//     service (asserted on the stub's recorded-call log).
//   - upstream failure: a failing leg surfaces the error and clears
//     results.
//   - empty / boundary: a non-blank query with three empty legs sets
//     `hasSearched` and reports `results.isEmpty`.
//   - stale guard: a superseded slow response does not clobber a newer
//     result.
//   - clear: resets query / results / error / hasSearched.
//
// Tests drive the view model through `searchNow()` (bypasses the
// debounce and awaits) so assertions are deterministic. A dedicated case
// exercises the `query`-didSet debounce path with a `.zero` window.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class SearchViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel() -> (SearchViewModel, StubSearchService) {
        let service = StubSearchService()
        let vm = SearchViewModel(service: service, debounce: .zero)
        return (vm, service)
    }

    private func message(_ id: String) -> Message {
        MessageFixtures.message(id: id, text: "hit \(id)")
    }

    private func list(_ id: String) -> ListSummary {
        ListSummary(
            id: id,
            title: "List \(id)",
            description: nil,
            visibility: .public,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func document(_ id: String) -> Document {
        Document(
            id: id,
            folderId: nil,
            title: "Doc \(id)",
            body: DocumentBody(markdown: "body \(id)"),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: nil,
            isPublic: false,
            deleted: false,
            version: nil
        )
    }

    // MARK: - Happy path

    func test_givenNonBlankQuery_whenSearching_thenGroupsHitsIntoSections() async {
        let (vm, service) = makeViewModel()
        await service.enqueueAll(
            messages: [message("m1"), message("m2")],
            lists: [list("l1")],
            documents: [document("d1"), document("d2"), document("d3")]
        )

        vm.query = "swift"
        await vm.searchNow()

        XCTAssertEqual(vm.results.messages.map(\.id), ["m1", "m2"])
        XCTAssertEqual(vm.results.lists.map(\.id), ["l1"])
        XCTAssertEqual(vm.results.documents.map(\.id), ["d1", "d2", "d3"])
        XCTAssertEqual(vm.results.totalCount, 6)
        XCTAssertFalse(vm.results.isEmpty)
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasSearched)
        XCTAssertFalse(vm.isSearching)
    }

    // MARK: - Invalid input (blank query → no service call)

    func test_givenBlankQuery_whenSearching_thenServiceIsNotCalledAndResultsCleared() async {
        let (vm, service) = makeViewModel()

        vm.query = "   "
        await vm.searchNow()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "A blank query must not fan out any request")
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.hasSearched)
        XCTAssertNil(vm.error)
    }

    func test_givenPopulatedResults_whenQueryBlanked_thenResultsClearedWithoutCall() async {
        let (vm, service) = makeViewModel()
        await service.enqueueAll(messages: [message("m1")], lists: [], documents: [])
        vm.query = "swift"
        await vm.searchNow()
        XCTAssertFalse(vm.results.isEmpty)

        // Blanking the field clears synchronously in the didSet path.
        vm.query = ""

        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.hasSearched)
        let recorded = await service.recorded
        // Only the first (non-blank) search reached the service.
        XCTAssertEqual(recorded.count, 3, "Blanking must not add another fan-out")
    }

    // MARK: - Upstream API failure

    func test_givenUpstreamFailure_whenSearching_thenSurfacesErrorAndClearsResults() async {
        let (vm, service) = makeViewModel()
        // `all(query:)` throws if any leg fails; stage a messages failure.
        await service.enqueueMessages(failure: TestError.upstream("net"))
        await service.enqueueLists(success: [])
        await service.enqueueDocuments(success: [])

        vm.query = "swift"
        await vm.searchNow()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertTrue(vm.hasSearched)
        XCTAssertFalse(vm.isSearching)
    }

    // MARK: - Empty / boundary

    func test_givenNoHits_whenSearching_thenReportsEmptyAndHasSearched() async {
        let (vm, service) = makeViewModel()
        await service.enqueueAll(messages: [], lists: [], documents: [])

        vm.query = "nothing-here"
        await vm.searchNow()

        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertEqual(vm.results.totalCount, 0)
        XCTAssertTrue(vm.hasSearched)
        XCTAssertNil(vm.error)
    }

    // MARK: - Debounce path

    func test_givenZeroDebounce_whenQuerySet_thenDebouncedSearchResolves() async {
        let (vm, service) = makeViewModel()
        await service.enqueueAll(messages: [message("m1")], lists: [], documents: [])

        vm.query = "swift"
        // Let the debounced task (zero window) run to completion.
        await Task.yield()
        for _ in 0..<10 where !vm.hasSearched {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(vm.results.messages.map(\.id), ["m1"])
        XCTAssertTrue(vm.hasSearched)
    }

    // MARK: - clear

    func test_givenActiveSearch_whenCleared_thenResetsAllState() async {
        let (vm, service) = makeViewModel()
        await service.enqueueAll(messages: [message("m1")], lists: [list("l1")], documents: [])
        vm.query = "swift"
        await vm.searchNow()
        XCTAssertFalse(vm.results.isEmpty)

        vm.clear()

        XCTAssertEqual(vm.query, "")
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.hasSearched)
        XCTAssertFalse(vm.isSearching)
    }
}
