// DocumentsListViewModelTests
//
// BDD-named view-model tests for the M4 Documents content list
// (PLAN.md §6 M4). Stubbed `DocumentsServicing`; no networking.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DocumentsListViewModelTests: XCTestCase {

    // MARK: - reload

    func test_givenLoadedDocuments_whenReloading_thenPopulatesList() async {
        // Happy path.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1", folderId: "F1", title: "Notes")
        await stub.enqueueDocuments(success: [doc])
        let viewModel = DocumentsListViewModel(documents: stub)

        await viewModel.reload(in: "F1")

        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1"])
        XCTAssertEqual(viewModel.folderID, "F1")
        XCTAssertNil(viewModel.error)
    }

    func test_givenEmptyResponse_whenReloading_thenLeavesListEmpty() async {
        // Empty boundary.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let viewModel = DocumentsListViewModel(documents: stub)

        await viewModel.reload(in: nil)

        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.hasMore)
    }

    func test_givenAPIFailure_whenReloading_thenSurfacesError() async {
        // Upstream failure.
        let stub = StubDocumentsService()
        let failure = TestError.upstream("denied")
        await stub.enqueueDocuments(failure: failure)
        let viewModel = DocumentsListViewModel(documents: stub)

        await viewModel.reload(in: nil)

        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
    }

    func test_givenFullPage_whenReloading_thenSurfacesHasMoreAndNextOffset() async {
        // Pagination boundary.
        let stub = StubDocumentsService()
        let page = (0..<DocumentsListViewModel.pageSize).map {
            DocumentsFixtures.document(id: "D\($0)")
        }
        await stub.enqueueDocuments(success: page)
        let viewModel = DocumentsListViewModel(documents: stub)

        await viewModel.reload(in: nil)

        XCTAssertTrue(viewModel.hasMore)
        XCTAssertEqual(viewModel.nextOffset, DocumentsListViewModel.pageSize)
    }

    // MARK: - createDocument

    func test_givenValidTitle_whenCreating_thenPrependsAndSelects() async {
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let created = DocumentsFixtures.document(id: "D1", title: "Notes")
        await stub.enqueueCreate(success: created)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        let result = await viewModel.createDocument(title: "Notes")

        XCTAssertEqual(result?.id, "D1")
        XCTAssertEqual(viewModel.documentsLoaded.first?.id, "D1")
        XCTAssertEqual(viewModel.selectedDocumentID, "D1")
        XCTAssertNil(viewModel.error)
    }

    func test_givenWhitespaceTitle_whenCreating_thenRejectsBeforeService() async {
        // Invalid input — service must not be called.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        let result = await viewModel.createDocument(title: "   ")

        XCTAssertNil(result)
        XCTAssertEqual(viewModel.error as? DocumentsUIError, .invalidDocumentTitle)
        let recorded = await stub.recorded
        let createCalls = recorded.filter {
            if case .create = $0.kind { return true } else { return false }
        }
        XCTAssertTrue(createCalls.isEmpty)
    }

    func test_givenAPIFailure_whenCreating_thenSurfacesError() async {
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let failure = TestError.upstream("denied")
        await stub.enqueueCreate(failure: failure)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        let result = await viewModel.createDocument(title: "Notes")

        XCTAssertNil(result)
        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
    }

    // MARK: - createDocument(from template:)

    func test_givenNamedTemplate_whenCreatingFromTemplate_thenSeedsTitleAndBody() async {
        // Happy path: the template's name becomes the title and its Markdown
        // becomes the body on the create call.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let template = DocumentTemplate.meetingNotes
        let created = DocumentsFixtures.document(
            id: "D1",
            title: template.name,
            body: template.bodyMarkdown
        )
        await stub.enqueueCreate(success: created)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        let result = await viewModel.createDocument(from: template)

        XCTAssertEqual(result?.id, "D1")
        XCTAssertEqual(viewModel.documentsLoaded.first?.id, "D1")
        XCTAssertEqual(viewModel.selectedDocumentID, "D1")
        XCTAssertNil(viewModel.error)

        let recorded = await stub.recorded
        let createCall = recorded.compactMap { call -> (String, String)? in
            if case let .create(title, body, _, _) = call.kind { return (title, body) }
            return nil
        }.first
        XCTAssertEqual(createCall?.0, template.name)
        XCTAssertEqual(createCall?.1, template.bodyMarkdown)
    }

    func test_givenBlankTemplate_whenCreatingFromTemplate_thenSeedsEmptyBody() async {
        // Boundary: the Blank template is the identity path — an empty body,
        // exactly like today's "new blank document" action.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let created = DocumentsFixtures.document(id: "D1", title: "Blank", body: "")
        await stub.enqueueCreate(success: created)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        let result = await viewModel.createDocument(from: .blank)

        XCTAssertEqual(result?.id, "D1")
        let recorded = await stub.recorded
        let createCall = recorded.compactMap { call -> (String, String)? in
            if case let .create(title, body, _, _) = call.kind { return (title, body) }
            return nil
        }.first
        XCTAssertEqual(createCall?.0, "Blank")
        XCTAssertEqual(createCall?.1, "")
    }

    func test_givenBlankTitleOverride_whenCreatingFromTemplate_thenRejectsBeforeService() async {
        // Invalid input: an explicit whitespace title override is rejected up
        // front (via the shared create guard) and no create call is made.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        let result = await viewModel.createDocument(from: .meetingNotes, title: "   ")

        XCTAssertNil(result)
        XCTAssertEqual(viewModel.error as? DocumentsUIError, .invalidDocumentTitle)
        let recorded = await stub.recorded
        let createCalls = recorded.filter {
            if case .create = $0.kind { return true } else { return false }
        }
        XCTAssertTrue(createCalls.isEmpty)
    }

    func test_givenAPIFailure_whenCreatingFromTemplate_thenSurfacesError() async {
        // Upstream failure: the service throws and the error surfaces; the
        // rendered list is untouched.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let failure = TestError.upstream("denied")
        await stub.enqueueCreate(failure: failure)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        let result = await viewModel.createDocument(from: .dailyLog)

        XCTAssertNil(result)
        XCTAssertEqual(viewModel.error as? TestError, failure)
        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
    }

    func test_givenExplicitTitle_whenCreatingFromTemplate_thenUsesOverrideNotTemplateName() async {
        // The caller may override the default (template name) title.
        let stub = StubDocumentsService()
        await stub.enqueueDocuments(success: [])
        let created = DocumentsFixtures.document(id: "D1", title: "Q3 Planning")
        await stub.enqueueCreate(success: created)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        _ = await viewModel.createDocument(from: .meetingNotes, title: "Q3 Planning")

        let recorded = await stub.recorded
        let createTitle = recorded.compactMap { call -> String? in
            if case let .create(title, _, _, _) = call.kind { return title }
            return nil
        }.first
        XCTAssertEqual(createTitle, "Q3 Planning")
    }

    // MARK: - deleteDocument

    func test_givenLoadedDocument_whenDeleting_thenRemovesAndClearsSelection() async {
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1")
        await stub.enqueueDocuments(success: [doc])
        await stub.enqueueDeleteSuccess()
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)
        viewModel.select(id: "D1")

        await viewModel.deleteDocument(id: "D1")

        XCTAssertTrue(viewModel.documentsLoaded.isEmpty)
        XCTAssertNil(viewModel.selectedDocumentID)
        XCTAssertNil(viewModel.error)
    }

    func test_givenDeleteFailure_whenDeleting_thenRestoresSnapshot() async {
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1")
        await stub.enqueueDocuments(success: [doc])
        let failure = TestError.upstream("denied")
        await stub.enqueueDelete(failure: failure)
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        await viewModel.deleteDocument(id: "D1")

        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1"])
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - apply(event:)

    func test_givenDeltaAppliedWithDelete_whenApplying_thenDropsAndReloads() async {
        // Event-bus routing: a deletedId arrives, the row disappears,
        // and the view model reloads the folder (via the stub).
        let stub = StubDocumentsService()
        let doc1 = DocumentsFixtures.document(id: "D1")
        let doc2 = DocumentsFixtures.document(id: "D2")
        await stub.enqueueDocuments(success: [doc1, doc2])
        // For the reload triggered by deltaApplied.
        await stub.enqueueDocuments(success: [doc2])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)
        viewModel.select(id: "D1")

        await viewModel.apply(event: .deltaApplied(
            insertedIds: [],
            updatedIds: [],
            deletedIds: ["D1"]
        ))

        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D2"])
        XCTAssertNil(viewModel.selectedDocumentID)
    }

    func test_givenPushedEvent_whenApplying_thenIsNoOp() async {
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1")
        await stub.enqueueDocuments(success: [doc])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        await viewModel.apply(event: .pushed(documentIds: ["D1"]))

        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1"])
    }

    func test_givenConflictResolvedEvent_whenApplying_thenIsNoOp() async {
        // Conflict events are consumed by the editor banner, not the
        // list. The list must not mutate.
        let stub = StubDocumentsService()
        let doc = DocumentsFixtures.document(id: "D1")
        await stub.enqueueDocuments(success: [doc])
        let viewModel = DocumentsListViewModel(documents: stub)
        await viewModel.reload(in: nil)

        await viewModel.apply(event: .conflictResolved(original: "D1", preservedAs: "D1-copy"))

        XCTAssertEqual(viewModel.documentsLoaded.map(\.id), ["D1"])
    }
}
