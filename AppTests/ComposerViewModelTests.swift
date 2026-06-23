// ComposerViewModelTests
//
// BDD-named view-model tests for the M2 composer window. View-model
// only — no SwiftUI rendering exercised. The view model is tested
// against `StubMessagesService` and the real `ComposerEventBus` so
// the event-emission half of the contract is covered by an
// integration assertion (subscribe before submit, then iterate one
// event off the stream).
//
// Quartet per behaviour: happy path, invalid input, upstream API
// failure, empty / boundary.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ComposerViewModelTests: XCTestCase {

    // MARK: - submit (new post)

    func test_givenValidBody_whenSubmittingNewPost_thenCallsCreateAndPostsEvent() async throws {
        // Given
        let stub = StubMessagesService()
        let created = MessageFixtures.message(id: "m-new", text: "hello")
        await stub.enqueueCreate(success: created)
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(messages: stub, eventBus: bus, mode: .newPost)
        viewModel.body = "hello"
        viewModel.visibility = .public

        // Subscribe before submit so we don't miss the emitted event.
        var iterator = bus.events().makeAsyncIterator()

        // When
        await viewModel.submit()

        // Then — the kit-level call was issued with the typed body.
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
        if case .create(let body, let parentId, let tags, let visibility, let pushed) = recorded.first?.kind {
            XCTAssertEqual(body, "hello")
            XCTAssertNil(parentId)
            XCTAssertEqual(tags, [])
            XCTAssertEqual(visibility, .public)
            XCTAssertNil(pushed)
        } else {
            XCTFail("Expected a `create` call, got \(String(describing: recorded.first))")
        }
        XCTAssertTrue(viewModel.didFinish)
        XCTAssertNil(viewModel.error)

        // And the event bus surfaced `.messageCreated`.
        let event = await iterator.next()
        if case .messageCreated(let message) = event {
            XCTAssertEqual(message.id, "m-new")
        } else {
            XCTFail("Expected `.messageCreated`, got \(String(describing: event))")
        }
    }

    func test_givenEmptyBody_whenSubmittingNewPost_thenNoCallIsMade() async {
        // Given — invalid input case: empty body.
        let stub = StubMessagesService()
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(messages: stub, eventBus: bus, mode: .newPost)
        viewModel.body = "   "

        // When
        await viewModel.submit()

        // Then — guard bailed out; no call, no finish.
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertFalse(viewModel.isPublishable)
    }

    func test_givenAPIFailure_whenSubmittingNewPost_thenSurfacesErrorAndDoesNotFinish() async {
        // Given — upstream API failure case.
        let stub = StubMessagesService()
        let failure = TestError.upstream("server down")
        await stub.enqueueCreate(failure: failure)
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(messages: stub, eventBus: bus, mode: .newPost)
        viewModel.body = "hello"

        // When
        await viewModel.submit()

        // Then
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    func test_givenWhitespaceOnlyBody_whenSubmitting_thenBoundaryRefusalLeavesIsSubmittingFalse() async {
        // Given — boundary: only whitespace and a leading newline.
        let stub = StubMessagesService()
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(messages: stub, eventBus: bus, mode: .newPost)
        viewModel.body = "\n  \t"

        // When
        await viewModel.submit()

        // Then
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertFalse(viewModel.didFinish)
    }

    // MARK: - submit (edit)

    func test_givenEditMode_whenSubmitting_thenCallsUpdateWithMessageId() async throws {
        // Given
        let original = MessageFixtures.message(id: "m-orig", text: "old", tags: ["swift"], visibility: .public)
        let stub = StubMessagesService()
        let updated = MessageFixtures.message(id: "m-orig", text: "new", tags: ["swift"], visibility: .private)
        await stub.enqueueUpdate(success: updated)
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(
            messages: stub,
            eventBus: bus,
            mode: .edit(messageID: original.id, original: original)
        )

        // The view model pre-populates from the original; mutate the
        // typed values to simulate user edits.
        viewModel.body = "new"
        viewModel.visibility = .private

        var iterator = bus.events().makeAsyncIterator()

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .update(let id, let body, _, let visibility) = recorded.first?.kind {
            XCTAssertEqual(id, "m-orig")
            XCTAssertEqual(body, "new")
            XCTAssertEqual(visibility, .private)
        } else {
            XCTFail("Expected an `update` call, got \(String(describing: recorded.first))")
        }
        XCTAssertTrue(viewModel.didFinish)

        let event = await iterator.next()
        if case .messageUpdated(let message) = event {
            XCTAssertEqual(message.text, "new")
        } else {
            XCTFail("Expected `.messageUpdated`, got \(String(describing: event))")
        }
    }

    func test_givenEditAPIFailure_whenSubmitting_thenSurfacesError() async {
        // Given
        let original = MessageFixtures.message(id: "m-x")
        let stub = StubMessagesService()
        let failure = TestError.upstream("forbidden")
        await stub.enqueueUpdate(failure: failure)
        let viewModel = ComposerViewModel(
            messages: stub,
            eventBus: ComposerEventBus(),
            mode: .edit(messageID: original.id, original: original)
        )
        viewModel.body = "new body"

        // When
        await viewModel.submit()

        // Then
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - Tag normalisation

    func test_givenCommaAndSpaceSeparated_whenNormalising_thenReturnsTokenList() {
        let tags = ComposerViewModel.normalise(tags: "swift, ios macos,, , swift")
        // Dedupes, preserves first-seen order.
        XCTAssertEqual(tags, ["swift", "ios", "macos"])
    }

    func test_givenHashPrefixedTags_whenNormalising_thenStripsHash() {
        let tags = ComposerViewModel.normalise(tags: "#swift #ios")
        XCTAssertEqual(tags, ["swift", "ios"])
    }

    func test_givenEmptyInput_whenNormalising_thenReturnsEmptyArray() {
        XCTAssertEqual(ComposerViewModel.normalise(tags: ""), [])
        XCTAssertEqual(ComposerViewModel.normalise(tags: "   \t  "), [])
    }
}
