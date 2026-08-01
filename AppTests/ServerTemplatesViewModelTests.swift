// ServerTemplatesViewModelTests
//
// BDD-named view-model tests for the server document-templates section of the
// "New from Template…" picker (the-gaps.md G12). Stubbed
// `DocumentTemplatesServicing` + `DocumentsServicing`; no networking.
//
// The quartet per behavior:
//   • load: happy / empty / non-fatal-failure / whitespace-path boundary
//   • create-from-template: happy / debounce-no-op / upstream-failure /
//     zero-new-docs boundary
//   • seed defaults: happy / failure

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ServerTemplatesViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(
        documentsStub: StubDocumentsService = StubDocumentsService(),
        templatesStub: StubDocumentTemplatesService = StubDocumentTemplatesService()
    ) -> (ServerTemplatesViewModel, DocumentsListViewModel, StubDocumentTemplatesService, StubDocumentsService) {
        let documentsList = DocumentsListViewModel(documents: documentsStub)
        let viewModel = ServerTemplatesViewModel(service: templatesStub, documentsList: documentsList)
        return (viewModel, documentsList, templatesStub, documentsStub)
    }

    // MARK: - loadTemplates

    func test_givenSavedTemplates_whenLoading_thenMapsAndSurfacesThem() async {
        // Happy path.
        let (sut, _, templates, _) = makeSUT()
        await templates.enqueueTemplates(success: [
            DocumentTemplateRef(id: "T1", title: "Weekly Review", relativePath: "_templates/weekly.md"),
            DocumentTemplateRef(id: "T2", title: "Bug Report", relativePath: "_templates/bug.md")
        ])

        await sut.loadTemplates()

        XCTAssertEqual(sut.templates.map(\.id), ["T1", "T2"])
        XCTAssertEqual(sut.templates.map(\.title), ["Weekly Review", "Bug Report"])
        XCTAssertNil(sut.loadError)
        XCTAssertTrue(sut.hasLoaded)
        XCTAssertFalse(sut.isEmpty)
    }

    func test_givenEmptyResponse_whenLoading_thenReportsEmptyStateWithoutError() async {
        // Empty boundary.
        let (sut, _, templates, _) = makeSUT()
        await templates.enqueueTemplates(success: [])

        await sut.loadTemplates()

        XCTAssertTrue(sut.templates.isEmpty)
        XCTAssertTrue(sut.isEmpty)
        XCTAssertTrue(sut.hasLoaded)
        XCTAssertNil(sut.loadError)
    }

    func test_givenAPIFailure_whenLoading_thenSurfacesLoadErrorNonFatally() async {
        // Upstream failure — non-fatal: templates stays empty, error is set,
        // and the picker keeps rendering the built-in section.
        let (sut, _, templates, _) = makeSUT()
        let failure = TestError.upstream("templates denied")
        await templates.enqueueTemplates(failure: failure)

        await sut.loadTemplates()

        XCTAssertEqual(sut.loadError as? TestError, failure)
        XCTAssertTrue(sut.templates.isEmpty)
        XCTAssertTrue(sut.hasLoaded)
        // Empty-state row is suppressed while a load error is showing (the view
        // prefers the error row), but the model still reports empty.
        XCTAssertTrue(sut.isEmpty)
    }

    func test_givenTemplateWithWhitespacePath_whenLoading_thenPreservesTitleAndPath() async {
        // Boundary: a template whose relativePath is nil / whitespace still maps
        // cleanly (the view guards the path display, the model does not mangle it).
        let (sut, _, templates, _) = makeSUT()
        await templates.enqueueTemplates(success: [
            DocumentTemplateRef(id: "T3", title: "Untitled Template", relativePath: nil)
        ])

        await sut.loadTemplates()

        XCTAssertEqual(sut.templates.first?.id, "T3")
        XCTAssertEqual(sut.templates.first?.title, "Untitled Template")
        XCTAssertNil(sut.templates.first?.relativePath)
    }

    // MARK: - createFromTemplate

    func test_givenServerTemplate_whenCreating_thenCallsServiceReloadsListAndReturnsNewDoc() async {
        // Happy path — create calls the service with the template id, reloads
        // the documents list, and returns + selects the newly-appeared doc.
        let documentsStub = StubDocumentsService()
        // The documents-list reload after create returns a page containing the
        // brand-new document (id "NEW") that was not present before.
        await documentsStub.enqueueDocuments(success: [
            DocumentsFixtures.document(id: "NEW", title: "From Template")
        ])
        let (sut, documentsList, templates, _) = makeSUT(documentsStub: documentsStub)
        await templates.enqueueCreateSuccess()
        let ref = DocumentTemplateRef(id: "T1", title: "Weekly Review")

        let created = await sut.createFromTemplate(ref)

        XCTAssertEqual(created?.id, "NEW")
        XCTAssertEqual(documentsList.selectedDocumentID, "NEW")
        XCTAssertNil(sut.createError)
        let recorded = await templates.recorded
        XCTAssertEqual(recorded, [.init(kind: .createFromTemplate(templateDocumentId: "T1"))])
    }

    func test_givenCreateAlreadyPending_whenCreatingSameTemplate_thenSecondCallIsNoOp() async {
        // Invalid / debounce — a second create for the same id while one is in
        // flight is rejected before touching the service (no second call).
        let documentsStub = StubDocumentsService()
        let templates = StubDocumentTemplatesService()
        let (sut, _, _, _) = makeSUT(documentsStub: documentsStub, templatesStub: templates)
        let ref = DocumentTemplateRef(id: "T1", title: "Weekly Review")

        // Stage exactly one create + one reload page; if the debounce leaks a
        // second call the stub's create queue drains and the second throws.
        await templates.enqueueCreateSuccess()
        await documentsStub.enqueueDocuments(success: [DocumentsFixtures.document(id: "NEW")])

        // Fire two creates for the same id concurrently. The debounce set makes
        // one of them a no-op.
        async let first = sut.createFromTemplate(ref)
        async let second = sut.createFromTemplate(ref)
        let results = await [first, second]

        let successes = results.compactMap { $0 }
        XCTAssertEqual(successes.count, 1, "exactly one create should reach the service")
        let createCalls = await templates.recorded.filter {
            $0 == .init(kind: .createFromTemplate(templateDocumentId: "T1"))
        }
        XCTAssertEqual(createCalls.count, 1, "the debounce set must suppress the duplicate call")
    }

    func test_givenAPIFailure_whenCreating_thenSurfacesCreateErrorAndDoesNotReload() async {
        // Upstream failure — the create throws, so `createError` is set, the
        // method returns nil, and the documents list is never reloaded.
        let documentsStub = StubDocumentsService()
        let (sut, documentsList, templates, _) = makeSUT(documentsStub: documentsStub)
        let failure = TestError.upstream("create denied")
        await templates.enqueueCreate(failure: failure)
        let ref = DocumentTemplateRef(id: "T1", title: "Weekly Review")

        let created = await sut.createFromTemplate(ref)

        XCTAssertNil(created)
        XCTAssertEqual(sut.createError as? TestError, failure)
        // No documents-reload happened (the list never fetched).
        let documentsCalls = await documentsStub.recorded.filter {
            if case .documents = $0.kind { return true }
            return false
        }
        XCTAssertTrue(documentsCalls.isEmpty)
        XCTAssertNil(documentsList.selectedDocumentID)
        // The pending debounce entry is released so a retry is possible.
        XCTAssertFalse(sut.pendingTemplateIDs.contains("T1"))
    }

    func test_givenReloadReturnsNoNewDocuments_whenCreating_thenFallsBackToFirstDoc() async {
        // Boundary — the reload page contains only pre-existing ids, so the
        // "first new id" lookup finds nothing and falls back to the first doc.
        let documentsStub = StubDocumentsService()
        // Seed the list so an id is already present before the create.
        await documentsStub.enqueueDocuments(success: [DocumentsFixtures.document(id: "OLD")])
        let (sut, documentsList, templates, _) = makeSUT(documentsStub: documentsStub)
        await documentsList.reload(in: nil)

        await templates.enqueueCreateSuccess()
        // The post-create reload returns the same single (pre-existing) doc.
        await documentsStub.enqueueDocuments(success: [DocumentsFixtures.document(id: "OLD")])
        let ref = DocumentTemplateRef(id: "T1", title: "Weekly Review")

        let created = await sut.createFromTemplate(ref)

        XCTAssertEqual(created?.id, "OLD", "falls back to the first loaded doc when no new id appears")
        XCTAssertNil(sut.createError)
    }

    // MARK: - seedDefaults

    func test_givenNoTemplates_whenSeedingDefaults_thenSeedsThenReloadsTemplates() async {
        // Happy path — seed calls the service then re-fetches so the seeded
        // templates appear.
        let (sut, _, templates, _) = makeSUT()
        await templates.enqueueSeedSuccess()
        await templates.enqueueTemplates(success: [
            DocumentTemplateRef(id: "S1", title: "Seeded Meeting Notes")
        ])

        await sut.seedDefaults()

        XCTAssertEqual(sut.templates.map(\.id), ["S1"])
        XCTAssertFalse(sut.isEmpty)
        XCTAssertNil(sut.loadError)
        let recorded = await templates.recorded
        XCTAssertEqual(recorded, [.init(kind: .seedDefaultTemplates), .init(kind: .templates)])
    }

    func test_givenAPIFailure_whenSeedingDefaults_thenSurfacesLoadErrorAndDoesNotReload() async {
        // Upstream failure — seed throws, error is surfaced non-fatally, and the
        // follow-up templates re-fetch never fires.
        let (sut, _, templates, _) = makeSUT()
        let failure = TestError.upstream("seed denied")
        await templates.enqueueSeed(failure: failure)

        await sut.seedDefaults()

        XCTAssertEqual(sut.loadError as? TestError, failure)
        XCTAssertFalse(sut.isLoading)
        let recorded = await templates.recorded
        XCTAssertEqual(recorded, [.init(kind: .seedDefaultTemplates)])
    }
}
