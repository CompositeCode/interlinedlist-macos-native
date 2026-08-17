// ListDetailViewModelTests
//
// BDD-named tests for `ListDetailViewModel`, focused on the public-list
// browser's view-mode toggle (work-consolidation.md §1b — bringing the
// owned-list grid to the read-only public view) and the column derivation
// that feeds the `Table` grid.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ListDetailViewModelTests: XCTestCase {

    private func makeViewModel(_ stub: StubListsService) -> ListDetailViewModel {
        ListDetailViewModel(lists: stub, username: "ada", slug: "bikes")
    }

    // MARK: - View mode

    func test_defaultViewMode_isCards() {
        let viewModel = makeViewModel(StubListsService())
        XCTAssertEqual(viewModel.viewMode, .cards)
    }

    func test_whenSwitchingToTable_thenViewModeSticks() {
        let viewModel = makeViewModel(StubListsService())
        viewModel.viewMode = .table
        XCTAssertEqual(viewModel.viewMode, .table)
    }

    // MARK: - Columns feed the grid

    func test_givenLoadedRows_thenColumnsAreSortedUnionOfFieldKeys() async {
        let stub = StubListsService()
        await stub.enqueuePublicList(success: ListsFixtures.listDetail(title: "Bikes"))
        await stub.enqueuePublicRows(success: ListsFixtures.rowsPage([
            ListsFixtures.row(id: "r1", fields: ["Title": .string("Trek"), "Year": .int(2024)]),
            ListsFixtures.row(id: "r2", fields: ["Brand": .string("Giant"), "Title": .string("Defy")])
        ]))
        let viewModel = makeViewModel(stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.id), ["r1", "r2"])
        // The grid's columns are the sorted union of field keys across rows.
        XCTAssertEqual(viewModel.columns, ["Brand", "Title", "Year"])
    }

    func test_givenSwitchToTableAfterLoad_thenRowsAndColumnsUnchanged() async {
        let stub = StubListsService()
        await stub.enqueuePublicList(success: ListsFixtures.listDetail())
        await stub.enqueuePublicRows(success: ListsFixtures.rowsPage([
            ListsFixtures.row(id: "r1", fields: ["Title": .string("Trek")])
        ]))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        viewModel.viewMode = .table

        XCTAssertEqual(viewModel.viewMode, .table)
        XCTAssertEqual(viewModel.rows.map(\.id), ["r1"])
        XCTAssertEqual(viewModel.columns, ["Title"])
    }
}
