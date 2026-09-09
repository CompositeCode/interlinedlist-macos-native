// PublicUserDocumentsViewModelTests
//
// BDD-named view-model tests for the profile's public-documents column
// (work-consolidation.md G24 — `GET /api/users/{username}/documents`).
//
// Stubbed `DocumentsServicing`; no networking, no SwiftUI rendering.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class PublicUserDocumentsViewModelTests: XCTestCase {

    // MARK: - Happy path

    func test_givenUserWithPublicDocuments_whenLoading_thenPaintsThemForThatHandle() async {
        let stub = StubDocumentsService()
        await stub.enqueuePublicDocuments(success: PublicUserDocuments(
            username: "adron",
            documents: [
                DocumentsFixtures.document(id: "D1", title: "Railroad Apps"),
                DocumentsFixtures.document(id: "D2", title: "Shows")
            ]
        ))
        let viewModel = PublicUserDocumentsViewModel(documents: stub)

        await viewModel.load(username: "adron")

        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1", "D2"])
        XCTAssertEqual(viewModel.username, "adron")
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.map(\.kind), [.publicDocuments(username: "adron")])
    }

    func test_givenHandleWithSurroundingWhitespace_whenLoading_thenTrimsBeforeCalling() async {
        let stub = StubDocumentsService()
        await stub.enqueuePublicDocuments(success: PublicUserDocuments(username: "adron"))
        let viewModel = PublicUserDocumentsViewModel(documents: stub)

        await viewModel.load(username: "  adron\n")

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.map(\.kind), [.publicDocuments(username: "adron")])
    }

    // MARK: - Invalid input

    func test_givenBlankHandle_whenLoading_thenRefusesBeforeTheService() async {
        // `/api/users//documents` is a different route entirely, so the guard
        // has to run here rather than being left to the server.
        let stub = StubDocumentsService()
        let viewModel = PublicUserDocumentsViewModel(documents: stub)

        await viewModel.load(username: "   ")

        XCTAssertEqual(viewModel.error as? DocumentsUIError, .invalidUsername)
        XCTAssertFalse(viewModel.hasLoaded)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - Upstream failure

    func test_givenAPIFailure_whenLoading_thenSurfacesTheErrorWithNoRows() async {
        let stub = StubDocumentsService()
        let failure = TestError.upstream("boom")
        await stub.enqueuePublicDocuments(failure: failure)
        let viewModel = PublicUserDocumentsViewModel(documents: stub)

        await viewModel.load(username: "adron")

        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
        XCTAssertTrue(viewModel.hasLoaded)
    }

    func test_givenASecondHandleThatFails_whenLoading_thenDoesNotShowTheFirstUsersDocuments() async {
        // Attributing one person's documents to another — even briefly — is
        // worse than showing nothing, so a failed switch clears the column.
        let stub = StubDocumentsService()
        await stub.enqueuePublicDocuments(success: PublicUserDocuments(
            username: "adron",
            documents: [DocumentsFixtures.document(id: "D1")]
        ))
        await stub.enqueuePublicDocuments(failure: TestError.upstream("boom"))
        let viewModel = PublicUserDocumentsViewModel(documents: stub)
        await viewModel.load(username: "adron")

        await viewModel.load(username: "someone-else")

        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
        XCTAssertEqual(viewModel.username, "someone-else")
    }

    // MARK: - Empty / boundary

    func test_givenUserWithNothingPublic_whenLoading_thenReportsEmptyRatherThanAnError() async {
        let stub = StubDocumentsService()
        await stub.enqueuePublicDocuments(success: PublicUserDocuments(username: "ghost"))
        let viewModel = PublicUserDocumentsViewModel(documents: stub)

        await viewModel.load(username: "ghost")

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(viewModel.hasLoaded, "empty must be distinguishable from not-yet-asked")
        XCTAssertNil(viewModel.error)
    }

    func test_givenNoLoadYet_whenAskedToRefresh_thenDoesNothing() async {
        // Boundary: `refresh()` before any handle has been browsed.
        let stub = StubDocumentsService()
        let viewModel = PublicUserDocumentsViewModel(documents: stub)

        await viewModel.refresh()

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertFalse(viewModel.hasLoaded)
    }

    func test_givenLoadedDocuments_whenCleared_thenReturnsToThePreLoadState() async {
        let stub = StubDocumentsService()
        await stub.enqueuePublicDocuments(success: PublicUserDocuments(
            username: "adron",
            documents: [DocumentsFixtures.document(id: "D1")]
        ))
        let viewModel = PublicUserDocumentsViewModel(documents: stub)
        await viewModel.load(username: "adron")

        viewModel.clear()

        XCTAssertNil(viewModel.username)
        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
        XCTAssertFalse(viewModel.hasLoaded)
        XCTAssertNil(viewModel.error)
    }
}
