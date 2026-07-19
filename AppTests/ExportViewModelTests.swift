// ExportViewModelTests
//
// BDD-named tests for the M7 ExportViewModel (PLAN.md §1 "Data Exports",
// §6 M7, §7 testing). Quartet per export type: happy + guard (no-op while
// in-flight) + upstream API failure + boundary (empty CSV).
//
// Tests view-model logic only — no SwiftUI rendering, no save panel.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ExportViewModelTests: XCTestCase {

    private func makeSUT() -> (ExportViewModel, StubExportsService) {
        let service = StubExportsService()
        let vm = ExportViewModel(exportsService: service, lists: StubListsService())
        return (vm, service)
    }

    /// SUT variant that exposes the lists stub for the Markdown-export path.
    private func makeMarkdownSUT() -> (ExportViewModel, StubListsService) {
        let lists = StubListsService()
        let vm = ExportViewModel(exportsService: StubExportsService(), lists: lists)
        return (vm, lists)
    }

    private func ownedList(id: String, title: String, schema: String?) -> OwnedList {
        OwnedList(id: id, title: title, description: nil, schemaDescription: schema)
    }

    private func row(_ id: String, _ fields: [String: ListCellValue]) -> ListRow {
        ListRow(id: id, listID: nil, fields: fields)
    }

    // MARK: - Happy path — each export type reaches the service and sets pendingExport

    func test_givenService_whenExportMessages_thenPendingExportSet() async throws {
        // Given
        let (vm, service) = makeSUT()
        service.enqueueMessages(success: .init(data: Data("id,content\n1,hello".utf8), contentType: "text/csv"))

        // When
        vm.export(.messages)
        // Allow async Task to complete.
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then — pendingExport populated, no error, service was called.
        XCTAssertNotNil(vm.pendingExport)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isExporting)
        XCTAssertEqual(service.recorded, [.messages])
    }

    func test_givenService_whenExportLists_thenPendingExportSet() async throws {
        let (vm, service) = makeSUT()
        service.enqueueLists()

        vm.export(.lists)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotNil(vm.pendingExport)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(service.recorded, [.lists])
    }

    func test_givenService_whenExportListDataRows_thenPendingExportSet() async throws {
        let (vm, service) = makeSUT()
        service.enqueueListDataRows()

        vm.export(.listDataRows)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotNil(vm.pendingExport)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(service.recorded, [.listDataRows])
    }

    func test_givenService_whenExportFollows_thenPendingExportSet() async throws {
        let (vm, service) = makeSUT()
        service.enqueueFollows()

        vm.export(.follows)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotNil(vm.pendingExport)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(service.recorded, [.follows])
    }

    // MARK: - Guard: no-op while another export is in flight

    func test_givenExportInFlight_whenExportCalledAgain_thenSecondCallIsDropped() async throws {
        // Given — first export is still in flight (service outcome not enqueued
        // yet so the Task is blocked). We call export a second time immediately.
        let (vm, service) = makeSUT()
        service.enqueueMessages()

        vm.export(.messages)
        // Second call while isExporting should be true.
        vm.export(.lists)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then — only messages was dispatched; lists was dropped.
        XCTAssertEqual(service.recorded, [.messages])
    }

    // MARK: - Upstream API failure

    func test_givenServiceFailure_whenExportMessages_thenErrorMessageSet() async throws {
        // Given — server rejects the session-auth export request.
        let (vm, service) = makeSUT()
        service.enqueueMessages(failure: TestError.upstream("session expired"))

        // When
        vm.export(.messages)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then — error surfaced; no pending export; isExporting cleared.
        XCTAssertNil(vm.pendingExport)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isExporting)
    }

    // MARK: - Boundary: empty CSV (zero rows exported)

    func test_givenEmptyCSV_whenExportMessages_thenPendingExportSetWithEmptyData() async throws {
        // Given — boundary: server returns an empty body (no messages).
        let (vm, service) = makeSUT()
        service.enqueueMessages(success: CSVExport(data: Data(), contentType: "text/csv"))

        // When
        vm.export(.messages)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then — empty data is a valid domain result; forward it for the save panel.
        let export = try XCTUnwrap(vm.pendingExport)
        XCTAssertTrue(export.data.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Error cleared on retry

    func test_givenPreviousError_whenExportCalledAgain_thenErrorMessageCleared() async throws {
        // Given — first call fails, leaving an error message.
        let (vm, service) = makeSUT()
        service.enqueueMessages(failure: TestError.upstream("timeout"))
        vm.export(.messages)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(vm.errorMessage)

        // When — user retries.
        service.enqueueMessages()
        vm.export(.messages)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then — stale error is cleared before the retry.
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.pendingExport)
    }

    // MARK: - Markdown export (feature-gaps.md §1.3)

    func test_givenOwnedListsWithRows_whenExportListsAsMarkdown_thenRendersTable() async throws {
        // Given one owned list with one row (no further pages).
        let (vm, lists) = makeMarkdownSUT()
        await lists.enqueueMyLists(success: .init(lists: [ownedList(id: "L1", title: "Films", schema: "Title:text, Year:number")], hasMore: false, nextOffset: nil))
        await lists.enqueueRows(success: .init(rows: [row("r1", ["Title": .string("Dune"), "Year": .int(1965)])], hasMore: false, nextOffset: nil))

        // When
        vm.exportListsAsMarkdown()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then — a Markdown document with the list heading and a schema-ordered table row.
        let export = try XCTUnwrap(vm.pendingMarkdownExport)
        XCTAssertEqual(export.filename, "interlinedlist-lists")
        XCTAssertTrue(export.text.contains("# Films"), export.text)
        XCTAssertTrue(export.text.contains("| Title | Year |"))
        XCTAssertTrue(export.text.contains("| Dune | 1965 |"))
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isExporting)
    }

    func test_givenNoOwnedLists_whenExportListsAsMarkdown_thenPendingSetWithEmptyText() async throws {
        // Given — boundary: the account owns no lists.
        let (vm, lists) = makeMarkdownSUT()
        await lists.enqueueMyLists(success: .empty)

        vm.exportListsAsMarkdown()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then — an empty document is still a valid export; no rows call was made.
        let export = try XCTUnwrap(vm.pendingMarkdownExport)
        XCTAssertTrue(export.text.isEmpty)
        XCTAssertNil(vm.errorMessage)
        let rowsCalls = await lists.recorded.contains { if case .rows = $0.kind { return true } else { return false } }
        XCTAssertFalse(rowsCalls)
    }

    func test_givenMyListsFailure_whenExportListsAsMarkdown_thenErrorSet() async throws {
        let (vm, lists) = makeMarkdownSUT()
        await lists.enqueueMyLists(failure: TestError.upstream("session expired"))

        vm.exportListsAsMarkdown()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(vm.pendingMarkdownExport)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isExporting)
    }

    func test_givenPaginatedListsAndRows_whenExportListsAsMarkdown_thenAllPagesFetched() async throws {
        // Given two pages of lists, the first list itself spanning two row pages.
        let (vm, lists) = makeMarkdownSUT()
        await lists.enqueueMyLists(success: .init(lists: [ownedList(id: "L1", title: "A", schema: "K:text")], hasMore: true, nextOffset: 1))
        await lists.enqueueRows(success: .init(rows: [row("r1", ["K": .string("one")])], hasMore: true, nextOffset: 1))
        await lists.enqueueRows(success: .init(rows: [row("r2", ["K": .string("two")])], hasMore: false, nextOffset: nil))
        await lists.enqueueMyLists(success: .init(lists: [ownedList(id: "L2", title: "B", schema: "K:text")], hasMore: false, nextOffset: nil))
        await lists.enqueueRows(success: .init(rows: [row("r3", ["K": .string("three")])], hasMore: false, nextOffset: nil))

        vm.exportListsAsMarkdown()
        try await Task.sleep(nanoseconds: 150_000_000)

        // Then — both lists and all rows appear; two myLists calls were made.
        let export = try XCTUnwrap(vm.pendingMarkdownExport)
        XCTAssertTrue(export.text.contains("# A"))
        XCTAssertTrue(export.text.contains("# B"))
        for value in ["one", "two", "three"] {
            XCTAssertTrue(export.text.contains("| \(value) |"), "missing row \(value): \(export.text)")
        }
        let myListsCalls = await lists.recorded.filter { if case .myLists = $0.kind { return true } else { return false } }
        XCTAssertEqual(myListsCalls.count, 2)
    }
}
