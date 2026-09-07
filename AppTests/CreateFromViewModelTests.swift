// CreateFromViewModelTests
//
// BDD tests for the "Create from…" sheet's view model (work-consolidation.md G16).
//
// The completeness gate gets more attention than a form gate usually would:
// this route rejects a malformed request with a message that describes the
// wrong thing ("Field at index 0 must have a 'key' property" even when one is
// present), so a user who reaches the server with an incomplete form gets no
// usable feedback. The gate has to hold locally.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class CreateFromViewModelTests: XCTestCase {

    private func makeViewModel(
        source: MaterializeSourceRef = .messages(ids: ["m1"]),
        service: StubMaterializeService = StubMaterializeService(),
        output: MaterializeOutput = .list,
        authorHandle: String? = "adron"
    ) -> CreateFromViewModel {
        CreateFromViewModel(
            source: source, materialize: service, output: output, authorHandle: authorHandle
        )
    }

    // MARK: - Defaults

    func test_givenMessageSource_whenOpened_thenStartsOnTheWebAppsDefaults() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.listTitle, "Message by @adron")
        XCTAssertEqual(viewModel.columns.map(\.name), ["Content", "Author", "Posted", "Links", "Tags"])
        XCTAssertEqual(viewModel.columns.map(\.type), [.textarea, .text, .text, .textarea, .text])
        XCTAssertTrue(viewModel.includeSourceData)
        XCTAssertFalse(viewModel.listIsPublic)
        XCTAssertTrue(viewModel.canCreate)
    }

    func test_givenManyMessages_whenOpened_thenTitleReadsForThePlural() {
        let viewModel = makeViewModel(source: .messages(ids: ["a", "b", "c"]))
        XCTAssertEqual(viewModel.listTitle, "3 messages")
    }

    func test_givenDocumentOutput_whenSwitchedFromList_thenTheTitleCarriesOver() {
        let viewModel = makeViewModel()
        viewModel.listTitle = "Renamed"

        viewModel.output = .both

        // Switching must not present an empty second title field.
        XCTAssertEqual(viewModel.documentTitle, "Message by @adron")
        XCTAssertTrue(viewModel.showsListSection)
        XCTAssertTrue(viewModel.showsDocumentSection)
    }

    // MARK: - Happy path

    func test_givenCompletedForm_whenCreated_thenSendsTheEditedSpec() async {
        let service = StubMaterializeService()
        await service.enqueue(MaterializeOutcome(listId: "l-1", listTitle: "Reading"))
        let viewModel = makeViewModel(service: service)
        viewModel.listTitle = "Reading"
        viewModel.listDescription = "Things to read"
        viewModel.listIsPublic = true
        viewModel.renameColumn(id: "content", to: "Body")
        viewModel.setColumnType(id: "author", to: .email)

        await viewModel.create()

        let specs = await service.recordedSpecs
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(specs.first?.list?.title, "Reading")
        XCTAssertEqual(specs.first?.list?.description, "Things to read")
        XCTAssertEqual(specs.first?.list?.isPublic, true)
        XCTAssertEqual(specs.first?.list?.columns.first?.name, "Body")
        XCTAssertEqual(specs.first?.list?.columns.first(where: { $0.key == "author" })?.type, .email)
        XCTAssertEqual(viewModel.outcome?.listId, "l-1")
        XCTAssertEqual(viewModel.outcomeSummary, "Created “Reading”.")
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_givenBothOutput_whenCreated_thenSummaryMentionsBoth() async {
        let service = StubMaterializeService()
        await service.enqueue(MaterializeOutcome(listId: "l", documentId: "d"))
        let viewModel = makeViewModel(service: service, output: .both)

        await viewModel.create()

        XCTAssertEqual(viewModel.outcomeSummary, "Created a list and a document.")
    }

    // MARK: - Column editing

    func test_givenAddedColumns_whenNamed_thenKeysStayUnique() {
        let viewModel = makeViewModel()
        viewModel.addColumn()
        viewModel.addColumn()

        let keys = viewModel.columns.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "column keys identify the column and must not collide")
    }

    func test_givenRemovedColumns_whenAllGone_thenCreateIsBlocked() {
        let viewModel = makeViewModel()
        for column in viewModel.columns { viewModel.removeColumn(id: column.id) }

        XCTAssertTrue(viewModel.columns.isEmpty)
        XCTAssertFalse(viewModel.canCreate)
    }

    func test_givenEditedColumns_whenReset_thenDefaultsComeBack() {
        let viewModel = makeViewModel()
        viewModel.removeColumn(id: "content")
        viewModel.renameColumn(id: "author", to: "Who")

        viewModel.restoreDefaultColumns()

        XCTAssertEqual(viewModel.columns.map(\.name), ["Content", "Author", "Posted", "Links", "Tags"])
    }

    // MARK: - Invalid input

    func test_givenBlankListTitle_whenChecked_thenCreateIsBlockedWithoutCallingTheServer() async {
        let service = StubMaterializeService()
        let viewModel = makeViewModel(service: service)
        viewModel.listTitle = "   "

        XCTAssertFalse(viewModel.canCreate)
        await viewModel.create()

        let specs = await service.recordedSpecs
        XCTAssertTrue(specs.isEmpty, "an incomplete form must not reach a route whose errors are unhelpful")
    }

    func test_givenBlankDocumentTitle_whenDocumentOutput_thenCreateIsBlocked() {
        let viewModel = makeViewModel(output: .document)
        viewModel.documentTitle = ""

        XCTAssertFalse(viewModel.canCreate)
    }

    // MARK: - Upstream failure

    func test_givenUnavailableSource_whenCreated_thenSurfacesTheServerMessage() async {
        let service = StubMaterializeService()
        struct ServerError: LocalizedError {
            var errorDescription: String? { "One or more messages are unavailable" }
        }
        await service.enqueue(failure: ServerError())
        let viewModel = makeViewModel(service: service)

        await viewModel.create()

        XCTAssertEqual(viewModel.errorMessage, "One or more messages are unavailable")
        XCTAssertNil(viewModel.outcome)
        XCTAssertTrue(viewModel.canCreate, "a failure leaves the form editable and re-submittable")
    }

    func test_givenIncompleteSpecError_whenSurfaced_thenMessageSaysWhatToFix() {
        XCTAssertEqual(
            CreateFromViewModel.message(for: MaterializeError.incompleteSpec),
            "Add a title and at least one column first."
        )
    }

    // MARK: - Empty / boundary

    func test_givenAcknowledgementWithNoIds_whenCreated_thenNoSuccessSummaryIsClaimed() async {
        let service = StubMaterializeService()
        await service.enqueue(MaterializeOutcome())
        let viewModel = makeViewModel(service: service)

        await viewModel.create()

        XCTAssertNil(viewModel.outcomeSummary, "an empty acknowledgement is not a success to announce")
        XCTAssertEqual(viewModel.outcome?.isEmpty, true)
    }

    func test_givenNoAuthorHandle_whenOpened_thenTitleStillReads() {
        let viewModel = makeViewModel(authorHandle: nil)
        XCTAssertEqual(viewModel.listTitle, "Message")
    }
}
