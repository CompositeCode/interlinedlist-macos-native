// FolderTreeSWRViewModelTests
//
// Stale-while-revalidate (SWR) view-model tests for the M4 Documents
// folder tree (PLAN.md §5, PASS 2). Exercises the cache-first paint added
// in PASS 2 via `StubDocumentsService.setCachedFolders`. View-model only.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class FolderTreeSWRViewModelTests: XCTestCase {

    // MARK: - Cache present

    func test_givenCachedFolders_whenInitialLoad_thenPaintsCacheWithoutBlockingSpinner() async {
        // Given
        let stub = StubDocumentsService()
        await stub.setCachedFolders([DocumentsFixtures.folder(id: "F1", name: "Cached")])
        await stub.enqueueFolders(success: [
            DocumentsFixtures.folder(id: "F1", name: "Fresh"),
            DocumentsFixtures.folder(id: "F2", name: "New")
        ])
        let viewModel = FolderTreeViewModel(documents: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertEqual(viewModel.folders.map(\.id), ["F1", "F2"])
        XCTAssertNil(viewModel.error)
        XCTAssertNotNil(viewModel.lastRefreshedAt)
    }

    // MARK: - Cold cache

    func test_givenEmptyCache_whenInitialLoad_thenUsesBlockingSpinnerThenData() async {
        // Given
        let stub = StubDocumentsService()
        await stub.enqueueFolders(success: [DocumentsFixtures.folder(id: "F1")])
        let viewModel = FolderTreeViewModel(documents: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertEqual(viewModel.folders.map(\.id), ["F1"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.refreshFailed)
    }

    // MARK: - Refresh error with cache

    func test_givenCachedFoldersAndRefreshFails_whenInitialLoad_thenKeepsFoldersAndSetsRefreshFailed() async {
        // Given
        let stub = StubDocumentsService()
        await stub.setCachedFolders([DocumentsFixtures.folder(id: "F1", name: "Cached")])
        await stub.enqueueFolders(failure: TestError.upstream("revalidate down"))
        let viewModel = FolderTreeViewModel(documents: stub)

        // When
        await viewModel.initialLoad()

        // Then — folders kept; non-blocking flag set; blocking error unset.
        XCTAssertEqual(viewModel.folders.map(\.id), ["F1"])
        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Cold cache + failure → blocking error

    func test_givenEmptyCacheAndNetworkFails_whenInitialLoad_thenSurfacesBlockingError() async {
        // Given
        let stub = StubDocumentsService()
        await stub.enqueueFolders(failure: TestError.upstream("boom"))
        let viewModel = FolderTreeViewModel(documents: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertTrue(viewModel.folders.isEmpty)
        XCTAssertEqual(viewModel.error as? TestError, .upstream("boom"))
        XCTAssertFalse(viewModel.refreshFailed)
    }

    // MARK: - Freshness TTL

    func test_givenFreshlyRefreshed_whenCheckingShouldRefresh_thenSkipsRevalidation() async {
        let stub = StubDocumentsService()
        await stub.enqueueFolders(success: [DocumentsFixtures.folder(id: "F1")])
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()
        XCTAssertFalse(viewModel.shouldRefresh)
    }
}
