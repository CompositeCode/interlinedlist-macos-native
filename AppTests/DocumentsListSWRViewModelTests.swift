// DocumentsListSWRViewModelTests
//
// Stale-while-revalidate (SWR) view-model tests for the M4 Documents
// content list (PLAN.md §5, PASS 2). Exercises the folder-scoped
// cache-first paint added in PASS 2 via
// `StubDocumentsService.setCachedDocuments(_:in:)`. View-model only.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DocumentsListSWRViewModelTests: XCTestCase {

    // MARK: - Cache present (folder-scoped)

    func test_givenCachedDocuments_whenReloadInFolder_thenPaintsCacheWithoutBlockingSpinner() async {
        // Given — a populated cache for folder F1 and a fresh network page.
        let stub = StubDocumentsService()
        await stub.setCachedDocuments(
            [DocumentsFixtures.document(id: "D1", folderId: "F1", title: "Cached")],
            in: "F1"
        )
        await stub.enqueueDocuments(success: [
            DocumentsFixtures.document(id: "D1", folderId: "F1", title: "Fresh"),
            DocumentsFixtures.document(id: "D2", folderId: "F1")
        ])
        let viewModel = DocumentsListViewModel(documents: stub)

        // When
        await viewModel.reload(in: "F1")

        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1", "D2"])
        XCTAssertNil(viewModel.error)
        XCTAssertNotNil(viewModel.lastRefreshedAt)
    }

    // MARK: - Cold folder (blocking spinner)

    func test_givenEmptyCacheForFolder_whenReloadInFolder_thenUsesBlockingSpinnerThenData() async {
        // Given — folder F2 has no cache; the network provides its first data.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [
            DocumentsFixtures.document(id: "D9", folderId: "F2")
        ])
        let viewModel = DocumentsListViewModel(documents: stub)

        // When
        await viewModel.reload(in: "F2")

        // Then
        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D9"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.refreshFailed)
    }

    // MARK: - Refresh error with cache

    func test_givenCachedDocumentsAndRefreshFails_whenReloadInFolder_thenKeepsRowsAndSetsRefreshFailed() async {
        // Given
        let stub = StubDocumentsService()
        await stub.setCachedDocuments(
            [DocumentsFixtures.document(id: "D1", folderId: "F1", title: "Cached")],
            in: "F1"
        )
        await stub.enqueueDocuments(failure: TestError.upstream("revalidate down"))
        let viewModel = DocumentsListViewModel(documents: stub)

        // When
        await viewModel.reload(in: "F1")

        // Then — rows kept; non-blocking flag set; blocking error unset.
        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1"])
        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Cold folder + failure → blocking error

    func test_givenEmptyCacheAndNetworkFails_whenReloadInFolder_thenSurfacesBlockingError() async {
        // Given
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(failure: TestError.upstream("boom"))
        let viewModel = DocumentsListViewModel(documents: stub)

        // When
        await viewModel.reload(in: "F3")

        // Then
        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
        XCTAssertEqual(viewModel.error as? TestError, .upstream("boom"))
        XCTAssertFalse(viewModel.refreshFailed)
    }

    // MARK: - Freshness TTL

    func test_givenFreshlyRefreshed_whenCheckingShouldRefresh_thenSkipsRevalidation() async {
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [DocumentsFixtures.document(id: "D1")])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)
        XCTAssertFalse(viewModel.shouldRefresh)
    }
}
