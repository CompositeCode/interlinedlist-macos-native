// RepostSheetViewModelTests
//
// BDD-named view-model tests for the M2 repost sheet. Covers
// commentary forwarding (and the `nil` mapping for an empty string),
// the empty-commentary boundary, and the upstream-failure path.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class RepostSheetViewModelTests: XCTestCase {

    func test_givenCommentary_whenSubmitting_thenCallsRepostWithTrimmedCommentary() async throws {
        // Given
        let stub = StubMessagesService()
        let reposted = MessageFixtures.message(id: "rp-1", text: "with note")
        await stub.enqueueRepost(success: reposted)
        let bus = ComposerEventBus()
        let viewModel = RepostSheetViewModel(
            messages: stub,
            eventBus: bus,
            originalMessageID: "m-orig"
        )
        viewModel.commentary = "  with note  "
        viewModel.visibility = .public
        var iterator = bus.events().makeAsyncIterator()

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .repost(let id, let commentary, let visibility) = recorded.first?.kind {
            XCTAssertEqual(id, "m-orig")
            XCTAssertEqual(commentary, "with note")
            XCTAssertEqual(visibility, .public)
        } else {
            XCTFail("Expected a `repost` call, got \(String(describing: recorded.first))")
        }
        XCTAssertTrue(viewModel.didFinish)

        let event = await iterator.next()
        if case .messageReposted(let message) = event {
            XCTAssertEqual(message.id, "rp-1")
        } else {
            XCTFail("Expected `.messageReposted`, got \(String(describing: event))")
        }
    }

    func test_givenEmptyCommentary_whenSubmitting_thenCallsRepostWithNilCommentary() async {
        // Given — boundary: empty commentary maps to `nil` per the
        // bare-repost convention the kit accepts.
        let stub = StubMessagesService()
        let reposted = MessageFixtures.message(id: "rp-2", text: "")
        await stub.enqueueRepost(success: reposted)
        let viewModel = RepostSheetViewModel(
            messages: stub,
            eventBus: ComposerEventBus(),
            originalMessageID: "m-orig"
        )
        viewModel.commentary = ""

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .repost(_, let commentary, _) = recorded.first?.kind {
            XCTAssertNil(commentary)
        } else {
            XCTFail("Expected a `repost` call, got \(String(describing: recorded.first))")
        }
    }

    func test_givenAPIFailure_whenSubmitting_thenSurfacesErrorAndDoesNotFinish() async {
        // Given — upstream API failure.
        let stub = StubMessagesService()
        let failure = TestError.upstream("blocked")
        await stub.enqueueRepost(failure: failure)
        let viewModel = RepostSheetViewModel(
            messages: stub,
            eventBus: ComposerEventBus(),
            originalMessageID: "m-orig"
        )
        viewModel.commentary = "anything"

        // When
        await viewModel.submit()

        // Then
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    func test_givenWhitespaceCommentary_whenSubmitting_thenStillSubmitsWithNilCommentary() async {
        // Given — boundary: whitespace-only commentary.
        let stub = StubMessagesService()
        let reposted = MessageFixtures.message(id: "rp-3", text: "")
        await stub.enqueueRepost(success: reposted)
        let viewModel = RepostSheetViewModel(
            messages: stub,
            eventBus: ComposerEventBus(),
            originalMessageID: "m-orig"
        )
        viewModel.commentary = "   \n  "

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .repost(_, let commentary, _) = recorded.first?.kind {
            XCTAssertNil(commentary)
        } else {
            XCTFail("Expected a `repost` call, got \(String(describing: recorded.first))")
        }
        XCTAssertTrue(viewModel.didFinish)
    }
}
