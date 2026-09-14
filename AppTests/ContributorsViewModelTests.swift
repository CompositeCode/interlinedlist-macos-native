// ContributorsViewModelTests
//
// BDD-named tests for the ranked contributor panel
// (work-consolidation.md G23 / issue #48).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ContributorsViewModelTests: XCTestCase {

    func test_givenRankedContributors_whenLoading_thenPreservesServerOrder() async {
        // The server owns the ranking formula; the client must not re-sort.
        let stub = StubListsService()
        await stub.enqueueContributors(success: [
            ListsFixtures.contributor(id: "c1", addedCount: 17, editedCount: 17, score: 34),
            ListsFixtures.contributor(id: "c2", addedCount: 2, editedCount: 0, score: 2)
        ])
        let viewModel = ContributorsViewModel(lists: stub, listId: "L1")

        await viewModel.load()

        XCTAssertEqual(viewModel.contributors.map(\.id), ["c1", "c2"])
        XCTAssertEqual(viewModel.totalScore, 36)
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.hasLoadedOnce)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.first?.kind, .contributors(listId: "L1"))
    }

    func test_givenNoContributors_whenLoading_thenLeavesEmptyAndTotalIsZero() async {
        // Boundary: a list nobody has touched. `totalScore == 0` is what the
        // view guards on before dividing to show a percentage.
        let stub = StubListsService()
        await stub.enqueueContributors(success: [])
        let viewModel = ContributorsViewModel(lists: stub, listId: "L1")

        await viewModel.load()

        XCTAssertTrue(viewModel.contributors.isEmpty)
        XCTAssertEqual(viewModel.totalScore, 0)
        XCTAssertTrue(viewModel.hasLoadedOnce)
    }

    func test_givenAPIFailure_whenLoading_thenSurfacesError() async {
        let stub = StubListsService()
        await stub.enqueueContributors(failure: TestError.upstream("denied"))
        let viewModel = ContributorsViewModel(lists: stub, listId: "L1")

        await viewModel.load()

        XCTAssertEqual(viewModel.error as? TestError, .upstream("denied"))
        XCTAssertTrue(viewModel.contributors.isEmpty)
    }

    func test_givenPriorFailure_whenRetrySucceeds_thenClearsErrorAndPopulates() async {
        // The panel's "Try Again" path.
        let stub = StubListsService()
        await stub.enqueueContributors(failure: TestError.upstream("boom"))
        await stub.enqueueContributors(success: [ListsFixtures.contributor(id: "c1", score: 3)])
        let viewModel = ContributorsViewModel(lists: stub, listId: "L1")
        await viewModel.load()

        await viewModel.load()

        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.contributors.map(\.id), ["c1"])
    }

    func test_givenContributorWithoutNames_whenLoading_thenFallsBackToNeutralLabel() async {
        // Invalid/partial upstream row: a contributor with no display name and
        // no username still renders a readable row.
        let stub = StubListsService()
        await stub.enqueueContributors(success: [
            ListsFixtures.contributor(id: "c1", username: nil, displayName: nil)
        ])
        let viewModel = ContributorsViewModel(lists: stub, listId: "L1")

        await viewModel.load()

        XCTAssertEqual(viewModel.contributors.first?.displayLabel, "Contributor")
    }
}
