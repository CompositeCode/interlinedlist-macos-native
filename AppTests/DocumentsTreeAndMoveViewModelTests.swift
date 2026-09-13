// DocumentsTreeAndMoveViewModelTests
//
// BDD-named view-model tests for the work-consolidation.md **G24** App-layer
// behaviour: the sidebar painting from the single tree call, per-folder
// document counts, `_templates` exclusion, moving a document between folders
// (including to root), and New Document routing to the folder route.
//
// Stubbed `DocumentsServicing`; no networking, no SwiftUI rendering.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DocumentsTreeAndMoveViewModelTests: XCTestCase {

    // MARK: - Sidebar: one call

    func test_givenTree_whenInitialLoad_thenPaintsFoldersFromASingleTreeCall() async {
        // Happy path. The assertion that matters is not just "folders
        // appeared" but that exactly one call — the tree — produced them.
        let stub = StubDocumentsService()
        await stub.enqueueTree(success: DocumentsFixtures.tree(
            folders: [(name: "Inbox", documents: ["Note"]), (name: "Receipts", documents: [])],
            rootDocuments: ["Unfiled"]
        ))
        let viewModel = FolderTreeViewModel(documents: stub)

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.folders.map(\.name), ["Inbox", "Receipts"])
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.map(\.kind), [.documentTree])
        XCTAssertNil(viewModel.error)
    }

    func test_givenNestedFolders_whenInitialLoad_thenProjectsTheHierarchy() async {
        let stub = StubDocumentsService()
        await stub.enqueueTree(success: DocumentsFixtures.tree(
            folders: [(name: "Parent", documents: []), (name: "Child", documents: [])],
            parents: ["Child": "Parent"]
        ))
        let viewModel = FolderTreeViewModel(documents: stub)

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.tree.roots.map(\.name), ["Parent"])
        XCTAssertEqual(viewModel.tree.children(of: "F-Parent").map(\.name), ["Child"])
    }

    // MARK: - Sidebar: document counts

    func test_givenTreeWithDocuments_whenLoaded_thenReportsPerFolderAndRootCounts() async {
        let stub = StubDocumentsService()
        await stub.enqueueTree(success: DocumentsFixtures.tree(
            folders: [(name: "Inbox", documents: ["A", "B"]), (name: "Empty", documents: [])],
            rootDocuments: ["Unfiled"]
        ))
        let viewModel = FolderTreeViewModel(documents: stub)

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.documentCount(for: "F-Inbox"), 2)
        // Boundary: an empty folder reports a real zero, not "unknown".
        XCTAssertEqual(viewModel.documentCount(for: "F-Empty"), 0)
        XCTAssertEqual(viewModel.documentCount(for: nil), 1)
    }

    func test_givenNoTreeYet_whenAskedForACount_thenReportsUnknownRatherThanZero() async {
        // Boundary: the difference between "this folder is empty" and "we
        // haven't fetched yet". A zero here would be a claim the view model
        // has not earned, and the sidebar would render a wrong badge.
        let stub = StubDocumentsService()
        let viewModel = FolderTreeViewModel(documents: stub)

        XCTAssertNil(viewModel.documentCount(for: "F-Inbox"))
        XCTAssertFalse(viewModel.hasTreeSnapshot)
    }

    // MARK: - Sidebar: `_templates`

    func test_givenTreeContainingTemplates_whenLoaded_thenItIsNeitherRenderedNorOfferedAsADestination() async {
        // Boundary from the issue: `_templates` comes back inline with real
        // folders. It is the server's template store — browsing into it or
        // filing a document there would be wrong in both directions.
        let stub = StubDocumentsService()
        await stub.enqueueTree(success: DocumentsFixtures.tree(
            folders: [(name: "Inbox", documents: []), (name: "_templates", documents: ["Recipe"])]
        ))
        let viewModel = FolderTreeViewModel(documents: stub)

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.folders.map(\.name), ["Inbox"])
        XCTAssertFalse(viewModel.moveDestinations.contains { $0.name == "_templates" })
        // Still discoverable for the template picker, which does want it.
        XCTAssertEqual(viewModel.templatesFolderID, "F-_templates")
    }

    func test_givenCachedFoldersIncludingTemplates_whenPaintingFromCache_thenTemplatesIsFilteredThereToo() async {
        // The cache is filled by the sync engine, which has no opinion about
        // `_templates`. Filtering only the network path would flash the folder
        // on screen and then remove it.
        let stub = StubDocumentsService()
        await stub.setCachedFolders([
            DocumentsFixtures.folder(id: "F1", name: "Inbox"),
            DocumentsFixtures.folder(id: "F2", name: "_templates")
        ])
        await stub.enqueueTree(failure: TestError.upstream("offline"))
        let viewModel = FolderTreeViewModel(documents: stub)

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.folders.map(\.name), ["Inbox"])
    }

    // MARK: - Sidebar: upstream failure

    func test_givenCachedFoldersAndFailingTree_whenLoaded_thenKeepsCacheAndFlagsRevalidationFailure() async {
        // Upstream-failure case from the issue: the tree call fails → the
        // sidebar paints from cache and shows a revalidation error, not an
        // empty tree.
        let stub = StubDocumentsService()
        await stub.setCachedFolders([DocumentsFixtures.folder(id: "F1", name: "Inbox")])
        await stub.enqueueTree(failure: TestError.upstream("tree down"))
        let viewModel = FolderTreeViewModel(documents: stub)

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.folders.map(\.id), ["F1"], "cached folders must stay on screen")
        XCTAssertTrue(viewModel.refreshFailed)
        // The blocking error surface stays clear — the sidebar is usable.
        XCTAssertNil(viewModel.error)
    }

    func test_givenColdCacheAndFailingTree_whenLoaded_thenSurfacesTheErrorWithAnEmptyTree() async {
        let stub = StubDocumentsService()
        let failure = TestError.upstream("tree down")
        await stub.enqueueTree(failure: failure)
        let viewModel = FolderTreeViewModel(documents: stub)

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.folders.isEmpty)
        XCTAssertFalse(viewModel.hasTreeSnapshot)
    }

    func test_givenEmptyAccount_whenLoaded_thenTreeIsEmptyWithoutError() async {
        let stub = StubDocumentsService()
        await stub.enqueueTree(success: DocumentsFixtures.tree())
        let viewModel = FolderTreeViewModel(documents: stub)

        await viewModel.initialLoad()

        XCTAssertTrue(viewModel.folders.isEmpty)
        XCTAssertEqual(viewModel.documentCount(for: nil), 0)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Move a document

    func test_givenDocumentInAFolder_whenMovedElsewhere_thenLeavesTheRenderedColumn() async {
        // Happy path: the column shows one folder, so a document moved out of
        // it no longer belongs there.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [
            DocumentsFixtures.document(id: "D1", folderId: "F1"),
            DocumentsFixtures.document(id: "D2", folderId: "F1")
        ])
        await stub.enqueueMove(success: DocumentsFixtures.document(id: "D1", folderId: "F2"))
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")

        let moved = await viewModel.moveDocument(id: "D1", to: "F2")

        XCTAssertEqual(moved?.folderId, "F2")
        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D2"])
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.contains { $0.kind == .moveDocument(id: "D1", toFolder: "F2") })
    }

    func test_givenDocumentInAFolder_whenMovedToRoot_thenSendsANilDestination() async {
        // "No folder (root)" — the destination the general update path cannot
        // express, so it is worth asserting the nil reaches the service.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [DocumentsFixtures.document(id: "D1", folderId: "F1")])
        await stub.enqueueMove(success: DocumentsFixtures.document(id: "D1", folderId: nil))
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")

        let moved = await viewModel.moveDocument(id: "D1", to: nil)

        XCTAssertNil(moved?.folderId)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.contains { $0.kind == .moveDocument(id: "D1", toFolder: nil) })
        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
    }

    func test_givenDocumentMovedIntoTheViewedFolder_whenMoved_thenRowStaysAndTakesTheServerCopy() async {
        // The mirror of the leaving case. The column shows F1 but is rendering
        // a row still marked as root — which happens right after a sync delta.
        // Moving it *into* F1 must keep the row and adopt the server's copy,
        // not drop a document the user is looking at.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [DocumentsFixtures.document(id: "D1", folderId: nil)])
        await stub.enqueueMove(
            success: DocumentsFixtures.document(id: "D1", folderId: "F1", title: "Server Title")
        )
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")

        let moved = await viewModel.moveDocument(id: "D1", to: "F1")

        XCTAssertEqual(moved?.folderId, "F1")
        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1"], "the row must stay in the column")
        XCTAssertEqual(
            viewModel.documentsLoaded.first?.title,
            "Server Title",
            "the row must adopt the server's copy, not keep the stale one"
        )
    }

    func test_givenDestinationEqualsCurrentFolder_whenMoved_thenNoServiceCallIsMade() async {
        // Invalid input: moving a document where it already is. Refused before
        // the service so the round-trip isn't spent changing nothing.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [DocumentsFixtures.document(id: "D1", folderId: "F1")])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")

        let moved = await viewModel.moveDocument(id: "D1", to: "F1")

        XCTAssertNil(moved)
        let recorded = await stub.recorded
        XCTAssertFalse(recorded.contains { if case .moveDocument = $0.kind { return true } else { return false } })
    }

    func test_givenUnknownDocumentId_whenMoved_thenNoServiceCallIsMade() async {
        // Boundary: the row was removed by a sync delta a moment earlier.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")

        let moved = await viewModel.moveDocument(id: "ghost", to: "F2")

        XCTAssertNil(moved)
        let recorded = await stub.recorded
        XCTAssertFalse(recorded.contains { if case .moveDocument = $0.kind { return true } else { return false } })
    }

    func test_givenDestinationFolderNoLongerExists_whenMoved_thenRestoresTheRowAndSurfacesTheError() async {
        // The issue's invalid case: move to a folder that no longer exists.
        // The optimistic removal has to roll back or the user loses sight of a
        // document that never moved.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [
            DocumentsFixtures.document(id: "D1", folderId: "F1"),
            DocumentsFixtures.document(id: "D2", folderId: "F1")
        ])
        let failure = TestError.upstream("Folder not found")
        await stub.enqueueMove(failure: failure)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")
        viewModel.select(id: "D1")

        let moved = await viewModel.moveDocument(id: "D1", to: "deleted-folder")

        XCTAssertNil(moved)
        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1", "D2"], "the row must come back")
        XCTAssertEqual(viewModel.selectedDocumentID, "D1", "the selection must come back too")
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - New Document inside a folder

    func test_givenAFolderIsSelected_whenCreatingADocument_thenUsesTheFolderRouteNotTheRootRoute() async {
        // The defect this closes: `POST /api/documents` always creates at root
        // and ignores any folderId, so the old call filed nothing in a folder.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        await stub.enqueueCreateInFolder(success: DocumentsFixtures.document(id: "D1", folderId: "F1"))
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")

        let created = await viewModel.createDocument(title: "Notes")

        XCTAssertEqual(created?.folderId, "F1")
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.contains {
            $0.kind == .createInFolder(
                folderId: "F1", title: "Notes", body: "", isPublic: false, relativePath: nil
            )
        })
        // And emphatically *not* the root create.
        XCTAssertFalse(recorded.contains { if case .create = $0.kind { return true } else { return false } })
    }

    func test_givenNoFolderSelected_whenCreatingADocument_thenUsesTheRootRoute() async {
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        await stub.enqueueCreate(success: DocumentsFixtures.document(id: "D1", folderId: nil))
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        let created = await viewModel.createDocument(title: "Notes")

        XCTAssertNil(created?.folderId)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.contains {
            $0.kind == .create(title: "Notes", body: "", folderId: nil, isPublic: false)
        })
        XCTAssertFalse(recorded.contains { if case .createInFolder = $0.kind { return true } else { return false } })
    }

    func test_givenBlankTitleAndAFolder_whenCreatingADocument_thenRefusesBeforeEitherRoute() async {
        // Invalid input: the guard must run before the routing decision, not
        // after it.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")

        let created = await viewModel.createDocument(title: "   ")

        XCTAssertNil(created)
        XCTAssertEqual(viewModel.error as? DocumentsUIError, .invalidDocumentTitle)
        let recorded = await stub.recorded
        XCTAssertFalse(recorded.contains { if case .createInFolder = $0.kind { return true } else { return false } })
    }

    func test_givenFreeAccount_whenCreatingInAFolder_thenSurfacesTheSubscriberError() async {
        // Upstream failure: the subscriber gate. The row must not appear in the
        // column, and the error must reach the view.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        await stub.enqueueCreateInFolder(failure: DocumentsError.subscriberRequired)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: "F1")

        let created = await viewModel.createDocument(title: "Notes")

        XCTAssertNil(created)
        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
        XCTAssertEqual(viewModel.error as? DocumentsError, .subscriberRequired)
    }
}
