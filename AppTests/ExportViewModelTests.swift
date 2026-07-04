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
        let vm = ExportViewModel(exportsService: service)
        return (vm, service)
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
}
