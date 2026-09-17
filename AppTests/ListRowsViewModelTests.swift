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
        XCTAssertEqual(viewModel.columns.map(\.key), ["Title"])
    }

    // MARK: - entityFields (schema-entity view, work-consolidation.md §1b)

    func test_givenSchemaWithVariedFields_whenEntityFields_thenProjectsTypesOptionsAndRequirement() async {
        let stub = StubListsService()
        let schema = ListSchema(fields: [
            SchemaField(name: "Title", type: .text),
            SchemaField(name: "Priority", type: .select, enumValues: ["low", "med", "high"]),
            SchemaField(name: "Email", type: .email, nullable: false),
            SchemaField(name: "Notes", type: .markdown, nullable: true)
        ])
        await stub.enqueueSchema(success: schema)
        await stub.enqueueRows(success: .empty)
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        let fields = viewModel.entityFields
        XCTAssertEqual(fields.map(\.name), ["Title", "Priority", "Email", "Notes"])
        // text — bare token, no options, no requirement badge (nullability unstated).
        XCTAssertEqual(fields[0].typeDescription, "text")
        XCTAssertTrue(fields[0].options.isEmpty)
        XCTAssertNil(fields[0].requirementLabel)
        // select — options folded into the description.
        XCTAssertEqual(fields[1].options, ["low", "med", "high"])
        XCTAssertEqual(fields[1].typeDescription, "select (low | med | high)")
        // email declared NOT NULL → "required".
        XCTAssertEqual(fields[2].typeDescription, "email")
        XCTAssertEqual(fields[2].requirementLabel, "required")
        // markdown nullable → "optional"; markdown carries no options.
        XCTAssertTrue(fields[3].options.isEmpty)
        XCTAssertEqual(fields[3].requirementLabel, "optional")
    }

    func test_givenEmptySchema_whenEntityFields_thenEmpty() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        await stub.enqueueRows(success: .empty)
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        XCTAssertTrue(viewModel.entityFields.isEmpty)
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
        XCTAssertEqual(viewModel.columns.map(\.key), ["A"])
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

    // MARK: - GitHub-backing detection + Add Row guard

    func test_givenRowWithGithubRepo_whenLoaded_thenIsGitHubBackedWithRepo() async {
        // Happy path: a synced row makes the list GitHub-backed and exposes the
        // repo the issue browser routes to.
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        let row = ListsFixtures.row(
            id: "R1", listId: "L1", fields: ["Title": .string("Bug")],
            source: "github", githubRepo: "CompositeCode/interlinedlist"
        )
        await stub.enqueueRows(success: RowsPage(rows: [row], hasMore: false, nextOffset: nil))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        XCTAssertTrue(viewModel.isGitHubBacked)
        XCTAssertEqual(viewModel.gitHubRepo, "CompositeCode/interlinedlist")
    }

    func test_givenPlainRows_whenLoaded_thenNotGitHubBacked() async {
        // Boundary: native rows leave the list plain, so Add Row stays active.
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        let row = ListsFixtures.row(id: "R1", listId: "L1", fields: ["A": .string("v")])
        await stub.enqueueRows(success: RowsPage(rows: [row], hasMore: false, nextOffset: nil))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        XCTAssertFalse(viewModel.isGitHubBacked)
        XCTAssertNil(viewModel.gitHubRepo)
    }

    func test_givenGitHubBackedList_whenAddRow_thenNoNativeRowCreated() async {
        // The guard: Add Row must not POST a native empty row on a GitHub-backed
        // list. It's a no-op — no createRow call, no optimistic row left behind.
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        let row = ListsFixtures.row(
            id: "R1", listId: "L1", fields: [:], githubRepo: "acme/widgets"
        )
        await stub.enqueueRows(success: RowsPage(rows: [row], hasMore: false, nextOffset: nil))
        // Enqueue a createRow outcome that must NOT be consumed.
        await stub.enqueueCreateRow(success: ListsFixtures.row(id: "SHOULD-NOT-APPEAR"))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")
        await viewModel.initialLoad()

        await viewModel.addRow()

        XCTAssertEqual(viewModel.rows.map(\.id), ["R1"], "rows unchanged; no optimistic row")
        let created = await stub.recorded.contains { if case .createRow = $0.kind { return true }; return false }
        XCTAssertFalse(created, "createRow must not be called on a GitHub-backed list")
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

// MARK: - Column key vs. label (GitHub #85)
//
// The lists UI used one `name` as both the header text and the `row.fields`
// subscript. That was correct only while the two were the same token — true for
// a schema typed as the client's DSL, false for one authored on the web, where
// the server keeps `propertyKey` and `propertyName` apart. Now that macOS can
// read a server-authored schema at all, a column labelled "Publication Year"
// over a key of `year` must still find its cell.

extension ListRowsViewModelTests {

    // Happy path

    func test_givenColumnsWhoseLabelDiffersFromKey_whenRendering_thenCellsStillResolve() async {
        let stub = StubListsService()
        let schema = ListSchema(fields: [
            SchemaField(key: "title", label: "Title", type: .text),
            SchemaField(key: "year", label: "Publication Year", type: .number)
        ])
        await stub.enqueueSchema(success: schema)
        let row = ListsFixtures.row(
            id: "R1",
            listId: "L1",
            fields: ["title": .string("Dune"), "year": .int(1965)]
        )
        await stub.enqueueRows(success: RowsPage(rows: [row], hasMore: false, nextOffset: nil))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        // The header shows the label; the subscript uses the key.
        XCTAssertEqual(viewModel.columns.map(\.label), ["Title", "Publication Year"])
        XCTAssertEqual(viewModel.columns.map(\.key), ["title", "year"])
        let loaded = try? XCTUnwrap(viewModel.rows.first)
        XCTAssertEqual(loaded?.fields[viewModel.columns[1].key], .int(1965))
        // The failure this guards against: looking the cell up by its label.
        XCTAssertNil(loaded?.fields["Publication Year"])
    }

    // Boundary — ordering and visibility come from the server

    func test_givenOutOfOrderAndHiddenColumns_whenRendering_thenOrderIsHonouredAndHiddenAreDropped() async {
        let stub = StubListsService()
        let schema = ListSchema(fields: [
            SchemaField(key: "c", label: "Third", type: .text, displayOrder: 2),
            SchemaField(key: "a", label: "First", type: .text, displayOrder: 0),
            SchemaField(key: "secret", label: "Hidden", type: .text, isVisible: false, displayOrder: 1)
        ])
        await stub.enqueueSchema(success: schema)
        await stub.enqueueRows(success: .empty)
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        // `displayOrder` is the authority, not array order — and a hidden column
        // keeps its data but does not take a column in the table.
        XCTAssertEqual(viewModel.columns.map(\.key), ["a", "c"])
    }

    // Invalid — a schema with no columns falls back to the observed row keys

    func test_givenNoSchema_whenRowsHaveKeys_thenColumnsUseTheKeysAsTheirOwnLabels() async {
        let stub = StubListsService()
        await stub.enqueueSchema(success: .empty)
        let row = ListsFixtures.row(id: "R1", listId: "L1", fields: ["b": .string("x"), "a": .string("y")])
        await stub.enqueueRows(success: RowsPage(rows: [row], hasMore: false, nextOffset: nil))
        let viewModel = ListRowsViewModel(lists: stub, eventBus: ListsEventBus(), listId: "L1")

        await viewModel.initialLoad()

        XCTAssertEqual(viewModel.columns.map(\.key), ["a", "b"])
        XCTAssertEqual(viewModel.columns.map(\.label), ["a", "b"], "with no schema the key is all there is")
    }
}
