// FolderTreeViewModelTests
//
// BDD-named view-model tests for the M4 Documents sidebar
// (PLAN.md §6 M4). Stubbed `DocumentsServicing`; no networking.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class FolderTreeViewModelTests: XCTestCase {

    // MARK: - initialLoad

    func test_givenLoadedFolders_whenInitialLoad_thenPopulatesTree() async {
        // Given — happy path.
        let stub = StubDocumentsService()
        let root = DocumentsFixtures.folder(id: "F1", name: "Inbox")
        let child = DocumentsFixtures.folder(id: "F2", name: "Receipts", parentId: "F1")
        await stub.enqueueFolders(success: [root, child])
        let viewModel = FolderTreeViewModel(documents: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertEqual(viewModel.folders.map(\.id), ["F1", "F2"])
        XCTAssertEqual(viewModel.tree.roots.map(\.id), ["F1"])
        XCTAssertEqual(viewModel.tree.children(of: "F1").map(\.id), ["F2"])
        XCTAssertNil(viewModel.error)
    }

    func test_givenEmptyResponse_whenInitialLoad_thenLeavesTreeEmpty() async {
        // Given — empty/boundary case.
        let stub = StubDocumentsService()
        await stub.enqueueFolders(success: [])
        let viewModel = FolderTreeViewModel(documents: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertTrue(viewModel.folders.isEmpty)
        XCTAssertTrue(viewModel.tree.roots.isEmpty)
        XCTAssertNil(viewModel.error)
    }

    func test_givenAPIFailure_whenInitialLoad_thenSurfacesError() async {
        // Given — upstream API failure.
        let stub = StubDocumentsService()
        let failure = TestError.upstream("boom")
        await stub.enqueueFolders(failure: failure)
        let viewModel = FolderTreeViewModel(documents: stub)

        // When
        await viewModel.initialLoad()

        // Then
        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.folders.isEmpty)
    }

    // MARK: - createFolder

    func test_givenValidName_whenCreatingFolder_thenAppendsToTree() async {
        // Happy path.
        let stub = StubDocumentsService()
        await stub.enqueueFolders(success: [])
        let created = DocumentsFixtures.folder(id: "F1", name: "Inbox")
        await stub.enqueueCreateFolder(success: created)
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()

        let result = await viewModel.createFolder(name: "Inbox", parentId: nil)

        XCTAssertEqual(result?.id, "F1")
        XCTAssertEqual(viewModel.folders.map(\.id), ["F1"])
        XCTAssertNil(viewModel.error)
    }

    func test_givenWhitespaceName_whenCreatingFolder_thenRejectsBeforeService() async {
        // Invalid-input case.
        let stub = StubDocumentsService()
        await stub.enqueueFolders(success: [])
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()

        let result = await viewModel.createFolder(name: "   ", parentId: nil)

        XCTAssertNil(result)
        XCTAssertEqual(viewModel.error as? DocumentsUIError, .invalidFolderName)
        // Service must not be called.
        let recorded = await stub.recorded
        let createCalls = recorded.filter {
            if case .createFolder = $0.kind { return true } else { return false }
        }
        XCTAssertTrue(createCalls.isEmpty)
    }

    func test_givenAPIFailure_whenCreatingFolder_thenSurfacesError() async {
        let stub = StubDocumentsService()
        await stub.enqueueFolders(success: [])
        let failure = TestError.upstream("denied")
        await stub.enqueueCreateFolder(failure: failure)
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()

        let result = await viewModel.createFolder(name: "Inbox", parentId: nil)

        XCTAssertNil(result)
        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.folders.isEmpty)
    }

    // MARK: - renameFolder

    func test_givenExistingFolder_whenRenaming_thenSwapsInPlace() async {
        let stub = StubDocumentsService()
        let folder = DocumentsFixtures.folder(id: "F1", name: "Old")
        await stub.enqueueFolders(success: [folder])
        let renamed = DocumentsFixtures.folder(id: "F1", name: "New")
        await stub.enqueueRenameFolder(success: renamed)
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()

        await viewModel.renameFolder(id: "F1", to: "New")

        XCTAssertEqual(viewModel.folders.first?.name, "New")
        XCTAssertNil(viewModel.error)
    }

    func test_givenRenameFailure_whenRenaming_thenRestoresSnapshot() async {
        let stub = StubDocumentsService()
        let folder = DocumentsFixtures.folder(id: "F1", name: "Old")
        await stub.enqueueFolders(success: [folder])
        let failure = TestError.upstream("denied")
        await stub.enqueueRenameFolder(failure: failure)
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()

        await viewModel.renameFolder(id: "F1", to: "New")

        XCTAssertEqual(viewModel.folders.first?.name, "Old")
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - deleteFolder

    func test_givenDeletedFolder_whenDeleting_thenRemovesAndClearsSelection() async {
        let stub = StubDocumentsService()
        let folder = DocumentsFixtures.folder(id: "F1", name: "Inbox")
        await stub.enqueueFolders(success: [folder])
        await stub.enqueueDeleteFolderSuccess()
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()
        viewModel.select(id: "F1")

        await viewModel.deleteFolder(id: "F1")

        XCTAssertTrue(viewModel.folders.isEmpty)
        XCTAssertNil(viewModel.selectedFolderID)
        XCTAssertNil(viewModel.error)
    }

    func test_givenDeleteFailure_whenDeleting_thenRestoresSnapshotAndSurfacesError() async {
        let stub = StubDocumentsService()
        let folder = DocumentsFixtures.folder(id: "F1", name: "Inbox")
        await stub.enqueueFolders(success: [folder])
        let failure = TestError.upstream("denied")
        await stub.enqueueDeleteFolder(failure: failure)
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()

        await viewModel.deleteFolder(id: "F1")

        XCTAssertEqual(viewModel.folders.map(\.id), ["F1"])
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - select

    func test_givenSelectedID_whenSelecting_thenUpdatesProperty() async {
        let stub = StubDocumentsService()
        await stub.enqueueFolders(success: [])
        let viewModel = FolderTreeViewModel(documents: stub)
        await viewModel.initialLoad()

        viewModel.select(id: "F42")

        XCTAssertEqual(viewModel.selectedFolderID, "F42")
    }
}
