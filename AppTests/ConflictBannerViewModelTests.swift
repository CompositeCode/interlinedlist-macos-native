// ConflictBannerViewModelTests
//
// BDD-named tests for the M4 conflict-banner lifecycle. The banner is
// state owned by `DocumentEditorViewModel.conflict`; the view
// (`ConflictBannerView`) renders it. The "Open the local copy" action
// fires a closure the parent view (`DocumentsRootView`) wires into the
// list view model — these tests verify the surface contract.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ConflictBannerViewModelTests: XCTestCase {

    // MARK: - state lifecycle

    func test_givenEditorBoundToDocument_whenConflictRecorded_thenBuildsBannerState() {
        // Happy path — the editor records the conflict, the banner
        // appears with the preserved id + title.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "Plan")
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)

        viewModel.recordConflict(preservedAs: "D1-copy", title: "Plan")

        XCTAssertEqual(viewModel.conflict?.preservedId, "D1-copy")
        XCTAssertEqual(viewModel.conflict?.preservedTitle, "Plan")
    }

    func test_givenNoConflictRecorded_whenBound_thenBannerStateIsNil() {
        // Empty boundary — a freshly-bound editor has no banner.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1")
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)

        viewModel.bind(to: doc)

        XCTAssertNil(viewModel.conflict)
    }

    func test_givenConflictRecorded_whenDismissed_thenBannerStateClears() {
        // Dismiss action — the banner disappears, no further side effect.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "Plan")
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)
        viewModel.recordConflict(preservedAs: "D1-copy", title: "Plan")

        viewModel.dismissConflict()

        XCTAssertNil(viewModel.conflict)
    }

    func test_givenRebindToFreshDocument_whenConflictWasOpen_thenBannerStateClears() {
        // Rebinding to a different document clears the previous
        // document's banner — otherwise it would bleed across docs.
        let stub = StubDocumentsService()
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: DocumentsFixtures.document(id: "D1", title: "Plan"))
        viewModel.recordConflict(preservedAs: "D1-copy", title: "Plan")

        viewModel.bind(to: DocumentsFixtures.document(id: "D2", title: "Other"))

        XCTAssertNil(viewModel.conflict)
    }

    // MARK: - event routing (event → state)

    func test_givenMatchingOriginalId_whenEventRouted_thenBannerHoldsPreservedId() {
        // The DocumentsRootView routes `conflictResolved` events whose
        // `original` matches `editor.document.id`. Simulate that here.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "Plan")
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)
        let event: DocumentSyncEvent = .conflictResolved(original: "D1", preservedAs: "D1-copy")

        if case .conflictResolved(let original, let preservedAs) = event, original == doc.id {
            viewModel.recordConflict(preservedAs: preservedAs, title: doc.title)
        }

        XCTAssertEqual(viewModel.conflict?.preservedId, "D1-copy")
    }

    func test_givenNonMatchingOriginalId_whenEventRouted_thenBannerStaysNil() {
        // Non-matching event must be a no-op — guarded at the routing
        // site (the parent view) but assert the state stays nil here.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", title: "Plan")
        let viewModel = DocumentEditorViewModel(documents: stub, debounce: .zero)
        viewModel.bind(to: doc)
        let event: DocumentSyncEvent = .conflictResolved(original: "OTHER", preservedAs: "OTHER-copy")

        if case .conflictResolved(let original, let preservedAs) = event, original == doc.id {
            viewModel.recordConflict(preservedAs: preservedAs, title: doc.title)
        }

        XCTAssertNil(viewModel.conflict)
    }
}
