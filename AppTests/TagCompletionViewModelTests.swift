// TagCompletionViewModelTests
//
// BDD-named tests for the composer's tag completion (work-consolidation.md G20),
// including the token parsing that decides *which* fragment gets completed.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class TagCompletionViewModelTests: XCTestCase {

    /// Zero debounce so tests do not wait on the real 200ms.
    private func makeViewModel(_ stub: StubTagsService?) -> TagCompletionViewModel {
        TagCompletionViewModel(service: stub, debounce: .zero)
    }

    /// Lets the debounced lookup task run to completion.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    // MARK: - Token parsing

    func test_givenPartialToken_whenParsing_thenActiveTokenIsTheTrailingFragment() {
        XCTAssertEqual(TagCompletionViewModel.activeToken(in: "swift ui swi"), "swi")
        XCTAssertEqual(TagCompletionViewModel.activeToken(in: "swift, ui, swi"), "swi")
        XCTAssertEqual(TagCompletionViewModel.activeToken(in: "#swi"), "swi", "a leading # is stripped")
    }

    func test_givenTrailingSeparator_whenParsing_thenNothingIsBeingTyped() {
        XCTAssertEqual(TagCompletionViewModel.activeToken(in: "swift "), "")
        XCTAssertEqual(TagCompletionViewModel.activeToken(in: "swift,"), "")
        XCTAssertEqual(TagCompletionViewModel.activeToken(in: ""), "")
    }

    func test_givenMixedInput_whenParsing_thenCommittedTokensExcludeTheOneBeingTyped() {
        XCTAssertEqual(TagCompletionViewModel.committedTokens(in: "swift ui swi"), ["swift", "ui"])
        // A trailing separator means every token is committed.
        XCTAssertEqual(TagCompletionViewModel.committedTokens(in: "swift ui "), ["swift", "ui"])
        XCTAssertEqual(TagCompletionViewModel.committedTokens(in: "#swift, #ui, sw"), ["swift", "ui"])
    }

    // MARK: - Happy path

    func test_givenPrefix_whenTyping_thenFetchesAndShowsSuggestions() async {
        let stub = StubTagsService()
        stub.enqueueSuggestions(success: ["swift", "swiftui"])
        let viewModel = makeViewModel(stub)

        viewModel.input(changed: "swi")
        await settle()

        XCTAssertEqual(viewModel.suggestions, ["swift", "swiftui"])
        XCTAssertTrue(viewModel.isShowing)
        XCTAssertEqual(stub.requestedPrefixes, ["swi"])
    }

    func test_givenSuggestion_whenApplied_thenReplacesTheTypedTokenAndLeavesTrailingSpace() {
        let viewModel = makeViewModel(StubTagsService())

        let result = viewModel.apply("swiftui", to: "swift swi")

        XCTAssertEqual(result, "swift swiftui ")
        XCTAssertFalse(viewModel.isShowing, "applying dismisses the popover")
    }

    // MARK: - Invalid input

    func test_givenShortOrEmptyPrefix_whenTyping_thenSkipsTheLookup() async {
        let stub = StubTagsService()
        let viewModel = makeViewModel(stub)

        viewModel.input(changed: "s")
        await settle()
        viewModel.input(changed: "swift ")
        await settle()

        XCTAssertTrue(stub.requestedPrefixes.isEmpty,
                      "a 1-character prefix matches most of the corpus; a trailing separator means nothing is being typed")
        XCTAssertFalse(viewModel.isShowing)
    }

    func test_givenAlreadyCommittedTag_whenSuggested_thenFiltersItOut() async {
        let stub = StubTagsService()
        stub.enqueueSuggestions(success: ["swift", "swiftui"])
        let viewModel = makeViewModel(stub)

        // "swift" is already in the field, so re-suggesting it is noise.
        viewModel.input(changed: "Swift swi")
        await settle()

        XCTAssertEqual(viewModel.suggestions, ["swiftui"], "match is case-insensitive")
    }

    func test_givenNoService_whenTyping_thenStaysSilent() async {
        let viewModel = makeViewModel(nil)

        viewModel.input(changed: "swi")
        await settle()

        XCTAssertFalse(viewModel.isShowing)
    }

    // MARK: - Upstream failure

    func test_givenLookupFailure_whenTyping_thenShowsNothingWithoutInterrupting() async {
        let stub = StubTagsService()
        stub.enqueueSuggestions(failure: URLError(.timedOut))
        let viewModel = makeViewModel(stub)

        viewModel.input(changed: "swi")
        await settle()

        // Completion is a nicety — a failed lookup must not surface an error
        // the user cannot act on mid-composition.
        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertFalse(viewModel.isShowing)
    }

    // MARK: - Empty / boundary

    func test_givenNoMatches_whenTyping_thenPopoverStaysHidden() async {
        let stub = StubTagsService()
        stub.enqueueSuggestions(success: [])
        let viewModel = makeViewModel(stub)

        viewModel.input(changed: "zzz")
        await settle()

        XCTAssertFalse(viewModel.isShowing)
    }

    func test_givenDismiss_whenCalled_thenClearsSuggestions() async {
        let stub = StubTagsService()
        stub.enqueueSuggestions(success: ["swift"])
        let viewModel = makeViewModel(stub)
        viewModel.input(changed: "swi")
        await settle()
        XCTAssertTrue(viewModel.isShowing)

        viewModel.dismiss()

        XCTAssertFalse(viewModel.isShowing)
    }
}
