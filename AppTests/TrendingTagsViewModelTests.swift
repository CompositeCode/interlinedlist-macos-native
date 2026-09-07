// TrendingTagsViewModelTests
//
// BDD-named tests for the timeline's trending-tags strip (work-consolidation.md G20).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class TrendingTagsViewModelTests: XCTestCase {

    // MARK: - Happy path

    func test_givenTrendingTags_whenLoading_thenPopulatesAndBecomesVisible() async {
        let stub = StubTagsService()
        stub.enqueueTrending(success: [
            TrendingTag(name: "swift", count: 42),
            TrendingTag(name: "swiftui", count: 17)
        ])
        let viewModel = TrendingTagsViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.tags.map(\.name), ["swift", "swiftui"])
        XCTAssertTrue(viewModel.isVisible)
    }

    // MARK: - Invalid / unavailable

    func test_givenNoService_whenLoading_thenStaysHidden() async {
        let viewModel = TrendingTagsViewModel(service: nil)

        await viewModel.load()

        XCTAssertFalse(viewModel.isVisible)
        XCTAssertTrue(viewModel.tags.isEmpty)
    }

    // MARK: - Upstream failure

    func test_givenFailure_whenLoading_thenHidesInsteadOfSurfacingAnError() async {
        let stub = StubTagsService()
        stub.enqueueTrending(failure: URLError(.notConnectedToInternet))
        let viewModel = TrendingTagsViewModel(service: stub)

        await viewModel.load()

        // Ambient decoration over the real feed must not push an error in front
        // of the user's timeline.
        XCTAssertFalse(viewModel.isVisible)
        XCTAssertTrue(viewModel.tags.isEmpty)
    }

    // MARK: - Empty / boundary

    func test_givenNoTrendingTags_whenLoading_thenStripStaysHidden() async {
        let stub = StubTagsService()
        stub.enqueueTrending(success: [])
        let viewModel = TrendingTagsViewModel(service: stub)

        await viewModel.load()

        XCTAssertFalse(viewModel.isVisible, "an empty strip must cost no vertical space")
    }
}
