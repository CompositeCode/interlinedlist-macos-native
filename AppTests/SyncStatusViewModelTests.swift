// SyncStatusViewModelTests
//
// BDD-named view-model tests for the M4 Documents toolbar sync status
// (PLAN.md §6 M4). Stubbed `DocumentsServicing`; no networking.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class SyncStatusViewModelTests: XCTestCase {

    // MARK: - syncNow

    func test_givenInitialState_whenObserved_thenIsIdle() {
        let stub = StubDocumentsService()
        let viewModel = SyncStatusViewModel(documents: stub)

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(viewModel.isSyncing)
    }

    func test_givenSyncSuccess_whenCallingSyncNow_thenTransitionsIdleToSyncingToLastSynced() async {
        // Happy path. Use a fixed clock so the assertion is stable.
        let stub = StubDocumentsService()
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_500)
        await stub.enqueueSync(success: DocumentsFixtures.emptyReport(lastSyncAt: syncedAt))
        let viewModel = SyncStatusViewModel(documents: stub, clock: { Date(timeIntervalSince1970: 1_700_000_600) })

        await viewModel.syncNow()

        if case .lastSynced(let at) = viewModel.state {
            XCTAssertEqual(at, syncedAt)
        } else {
            XCTFail("Expected .lastSynced, got \(viewModel.state)")
        }
        XCTAssertFalse(viewModel.isSyncing)
    }

    func test_givenSyncSuccessWithoutTimestamp_whenCallingSyncNow_thenFallsBackToClock() async {
        // Boundary — `lastSyncAt` is nil; the view model falls back to
        // the injected clock so the status indicator still has a value.
        let stub = StubDocumentsService()
        let clockNow = Date(timeIntervalSince1970: 1_700_000_999)
        await stub.enqueueSync(success: DocumentsFixtures.emptyReport(lastSyncAt: nil))
        let viewModel = SyncStatusViewModel(documents: stub, clock: { clockNow })

        await viewModel.syncNow()

        if case .lastSynced(let at) = viewModel.state {
            XCTAssertEqual(at, clockNow)
        } else {
            XCTFail("Expected .lastSynced, got \(viewModel.state)")
        }
    }

    func test_givenSyncFailure_whenCallingSyncNow_thenSurfacesFailedState() async {
        // Upstream failure — state transitions to .failed with the
        // error's localized description.
        let stub = StubDocumentsService()
        await stub.enqueueSync(failure: TestError.upstream("offline"))
        let viewModel = SyncStatusViewModel(documents: stub)

        await viewModel.syncNow()

        if case .failed(let message) = viewModel.state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(viewModel.state)")
        }
    }

    func test_givenExternalSyncSuccess_whenRecording_thenStateIsLastSynced() {
        // Triggered by the documents event loop after the on-launch
        // auto-sync — the status indicator advances even though the
        // user didn't click "Sync Now."
        let stub = StubDocumentsService()
        let viewModel = SyncStatusViewModel(documents: stub)
        let when = Date(timeIntervalSince1970: 1_700_001_111)

        viewModel.recordExternalSyncSuccess(at: when)

        if case .lastSynced(let at) = viewModel.state {
            XCTAssertEqual(at, when)
        } else {
            XCTFail("Expected .lastSynced, got \(viewModel.state)")
        }
    }
}
