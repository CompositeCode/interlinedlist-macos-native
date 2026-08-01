// ListRowsViewModelTests
//
// BDD-named tests for the M3 rows table view model.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ListRowsViewModelTests: XCTestCase {

    // MARK: - initialLoad

    func test_givenLoadedSchemaAndRows_whenInitialLoad_thenPopulates() async {
        let stub = StubListsService()
        let schema = ListSchema(fields: [SchemaField(name: "Title", type: .text)])
        await stub.enqueueSchema(success: schema)
        let row = ListsFixtures.row(id: "R1", listId: "L1", fields: ["Title": .string("Hi")])
        await stub.enqueueRows(success: RowsPage(rows: [row], hasMore: false, nextOffset: nil))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.rows.map(\.id), ["R1"])
        XCTAssertEqual(viewModel.schema.fields.map(\.name), ["Title"])
        XCTAssertEqual(viewModel.columns, ["Title"])
    }

    func test_givenEmptyRows_whenInitialLoad_thenColumnsFallBackToEmpty() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        await stub.enqueueRows(success: .empty)
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertTrue(viewModel.columns.isEmpty)
    }

    func test_givenSchemaFailureAndRowsSuccess_whenInitialLoad_thenRowsStillRender() async {
        // Boundary — schema failure tolerated; rows still load.
        let stub = StubListsService()
        await stub.enqueueSchema(failure: ListsError.malformedSchema(raw: "x", reason: .emptySource))
        let row = ListsFixtures.row(id: "R1", listId: "L1", fields: ["A": .string("v")])
        await stub.enqueueRows(success: RowsPage(rows: [row], hasMore: false, nextOffset: nil))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertTrue(viewModel.schema.fields.isEmpty)
        XCTAssertEqual(viewModel.columns, ["A"])
    }

    // MARK: - addRow optimistic insert

    func test_givenLoadedRows_whenAddRow_thenAppendsAndReplacesWithServer() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        await stub.enqueueRows(success: .empty)
        let serverRow = ListsFixtures.row(id: "R-server", listId: "L1", fields: [:])
        await stub.enqueueCreateRow(success: serverRow)
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.initialLoad()

        await viewModel.addRow()

        XCTAssertEqual(viewModel.rows.map(\.id), ["R-server"])
        XCTAssertEqual(viewModel.selectedRowID, "R-server")
    }

    func test_givenAddRowFailure_whenAddRow_thenRestoresSnapshot() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        await stub.enqueueRows(success: .empty)
        await stub.enqueueCreateRow(failure: TestError.upstream("denied"))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.initialLoad()

        await viewModel.addRow()

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.error as? TestError, .upstream("denied"))
    }

    // MARK: - updateRow optimistic + rollback

    func test_givenUpdateSuccess_whenUpdating_thenReplacesWithServerCopy() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        let original = ListsFixtures.row(id: "R1", listId: "L1", fields: ["A": .string("old")])
        await stub.enqueueRows(success: RowsPage(rows: [original], hasMore: false, nextOffset: nil))
        let serverCopy = ListsFixtures.row(id: "R1", listId: "L1", fields: ["A": .string("server")])
        await stub.enqueueUpdateRow(success: serverCopy)
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.initialLoad()

        await viewModel.updateRow(id: "R1", fields: ["A": .string("new")])

        XCTAssertEqual(viewModel.rows.first?.fields["A"], .string("server"))
    }

    func test_givenUpdateFailure_whenUpdating_thenRestoresSnapshotAndSurfacesError() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        let original = ListsFixtures.row(id: "R1", listId: "L1", fields: ["A": .string("old")])
        await stub.enqueueRows(success: RowsPage(rows: [original], hasMore: false, nextOffset: nil))
        await stub.enqueueUpdateRow(failure: TestError.upstream("denied"))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.initialLoad()

        await viewModel.updateRow(id: "R1", fields: ["A": .string("new")])

        XCTAssertEqual(viewModel.rows.first?.fields["A"], .string("old"))
        XCTAssertEqual(viewModel.error as? TestError, .upstream("denied"))
    }

    // MARK: - deleteRows

    func test_givenSelection_whenDeletingRows_thenRemovesFromList() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        let a = ListsFixtures.row(id: "R1", listId: "L1")
        let b = ListsFixtures.row(id: "R2", listId: "L1")
        await stub.enqueueRows(success: RowsPage(rows: [a, b], hasMore: false, nextOffset: nil))
        await stub.enqueueDeleteRowSuccess()
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.initialLoad()

        await viewModel.deleteRows(ids: ["R1"])

        XCTAssertEqual(viewModel.rows.map(\.id), ["R2"])
    }

    // MARK: - parse helper

    func test_givenNumericString_whenParsingAsNumber_thenReturnsInt() {
        XCTAssertEqual(ListRowsViewModel.parse("42", as: .number), .int(42))
    }

    func test_givenDecimalString_whenParsingAsNumber_thenReturnsDouble() {
        XCTAssertEqual(ListRowsViewModel.parse("3.14", as: .number), .double(3.14))
    }

    func test_givenWhitespace_whenParsing_thenReturnsNull() {
        XCTAssertEqual(ListRowsViewModel.parse("   ", as: .text), .null)
    }

    func test_givenBoolean_whenParsingAsBoolean_thenReturnsBool() {
        XCTAssertEqual(ListRowsViewModel.parse("yes", as: .boolean), .bool(true))
        XCTAssertEqual(ListRowsViewModel.parse("0", as: .boolean), .bool(false))
    }

    func test_givenSelectOption_whenParsingAsSelect_thenReturnsString() {
        // §1.1 — a select cell stores the chosen option's raw text.
        XCTAssertEqual(ListRowsViewModel.parse("high", as: .select), .string("high"))
    }

    func test_givenMarkdownSource_whenParsingAsMarkdown_thenReturnsString() {
        // §1.1 — a markdown cell stores raw Markdown source verbatim.
        XCTAssertEqual(ListRowsViewModel.parse("# Title", as: .markdown), .string("# Title"))
    }

    func test_givenWhitespace_whenParsingAsSelectOrMarkdown_thenReturnsNull() {
        // Boundary — a cleared select/markdown cell projects to null.
        XCTAssertEqual(ListRowsViewModel.parse("   ", as: .select), .null)
        XCTAssertEqual(ListRowsViewModel.parse("", as: .markdown), .null)
    }

    // MARK: - apply(event:)

    func test_givenRowEventForOtherList_whenApplied_thenIsNoop() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        await stub.enqueueRows(success: .empty)
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.initialLoad()

        viewModel.apply(event: .rowCreated(listId: "OTHER", row: ListsFixtures.row(id: "X")))

        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    func test_givenSchemaChangedEvent_whenApplied_thenReplacesSchema() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        await stub.enqueueRows(success: .empty)
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.initialLoad()

        let newSchema = ListSchema(fields: [SchemaField(name: "Z", type: .number)])
        viewModel.apply(event: .schemaChanged(listId: "L1", schema: newSchema))

        XCTAssertEqual(viewModel.schema.fields.map(\.name), ["Z"])
    }
}
