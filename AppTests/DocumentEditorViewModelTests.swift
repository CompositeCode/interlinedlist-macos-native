// DocumentEditorViewModelTests
//
// BDD-named view-model tests for the M4 Documents editor + preview
// (PLAN.md §6 M4). Uses `debounce: .zero` so saves fire on the next
// event-loop turn — production code uses 1.5s.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DocumentEditorViewModelTests: XCTestCase {

    // MARK: - bind

    func test_givenBoundDocument_whenBinding_thenPopulatesBufferAndClearsDirty() async {
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "Title", body: "Body")
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)

        viewModel.bind(to: doc)

        XCTAssertEqual(viewModel.title, "Title")
        XCTAssertEqual(viewModel.body, "Body")
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertNil(viewModel.error)
    }

    func test_givenNilDocument_whenBinding_thenClearsBuffer() async {
        let stub = StubDocumentsService()
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: DocumentsFixtures.document(id: "D1", title: "Title"))

        viewModel.bind(to: nil)

        XCTAssertEqual(viewModel.title, "")
        XCTAssertEqual(viewModel.body, "")
        XCTAssertNil(viewModel.document)
    }

    // MARK: - debounced save

    func test_givenBodyEdit_whenDebounceElapses_thenCallsUpdate() async {
        // Happy path. Use debounce: .zero so the save fires on the
        // next loop turn.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "T", body: "Original")
        let updated = DocumentsFixtures.document(id: "D1", title: "T", body: "Original edited")
        await stub.enqueueUpdate(success: updated)
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)

        viewModel.body = "Original edited"

        // Yield until the pending save has had a chance to run + return.
        await waitForSaveCompletion(viewModel: viewModel)

        XCTAssertEqual(viewModel.body, "Original edited")
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        let updates = recorded.filter {
            if case .update = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(updates.count, 1)
    }

    func test_givenNoChanges_whenSaveNow_thenDoesNotCallUpdate() async {
        // Boundary: saveNow on a clean buffer is a no-op so we don't
        // hammer the service on every focus change.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "T", body: "B")
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)

        await viewModel.saveNow()

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenSaveFailure_whenSaving_thenLeavesBufferDirtyAndSurfacesError() async {
        // Upstream failure — the buffer stays dirty so the next
        // keystroke retries.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "T", body: "B")
        let failure = TestError.upstream("denied")
        await stub.enqueueUpdate(failure: failure)
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)

        viewModel.title = "T2"
        await viewModel.saveNow()

        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.title, "T2")
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - uploadImage

    func test_givenValidImage_whenUploading_thenAppendsMarkdownReference() async {
        // Happy path.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", body: "Existing")
        await stub.enqueueUploadImage(success: URL(string: "https://example.com/img.png")!)
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)

        let url = await viewModel.uploadImage(Data([0x89, 0x50]), suggestedName: "screenshot.png")

        XCTAssertEqual(url?.absoluteString, "https://example.com/img.png")
        XCTAssertTrue(viewModel.body.contains("![screenshot.png](https://example.com/img.png)"))
    }

    func test_givenNoDocument_whenUploading_thenRejectsBeforeService() async {
        // Invalid input — no bound document. Service must not be called.
        let stub = StubDocumentsService()
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)

        let url = await viewModel.uploadImage(Data(), suggestedName: nil)

        XCTAssertNil(url)
        let recorded = await stub.recorded
        let uploads = recorded.filter {
            if case .uploadImage = $0.kind { return true } else { return false }
        }
        XCTAssertTrue(uploads.isEmpty)
    }

    func test_givenImageTooLarge_whenUploading_thenSurfacesUIError() async {
        // Domain error translation — the DocumentsError.imageTooLargeAfterPrep
        // becomes DocumentsUIError so the banner copy stays uniform.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1")
        await stub.enqueueUploadImage(failure: DocumentsError.imageTooLargeAfterPrep)
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)

        let url = await viewModel.uploadImage(Data(), suggestedName: nil)

        XCTAssertNil(url)
        XCTAssertEqual(viewModel.error as? DocumentsUIError, .imageTooLargeAfterPrep)
    }

    func test_givenAPIFailure_whenUploading_thenSurfacesError() async {
        // Upstream failure not translated to a domain case.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1")
        let failure = TestError.upstream("network down")
        await stub.enqueueUploadImage(failure: failure)
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)

        _ = await viewModel.uploadImage(Data(), suggestedName: nil)

        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - conflict banner

    func test_givenConflictRecorded_whenDismissing_thenClearsBanner() async {
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "Plan")
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)

        viewModel.recordConflict(preservedAs: "D1-copy", title: "Plan")
        XCTAssertEqual(viewModel.conflict?.preservedId, "D1-copy")

        viewModel.dismissConflict()

        XCTAssertNil(viewModel.conflict)
    }

    // MARK: - Helpers

    /// Yields the runloop several times so the debounce task + the
    /// service round-trip both have a chance to complete. With
    /// `debounce: .zero`, two-three turns is enough.
    private func waitForSaveCompletion(viewModel: DocumentEditorViewModel) async {
        for _ in 0..<8 {
            await Task.yield()
            if !viewModel.hasUnsavedChanges { return }
        }
    }
}
