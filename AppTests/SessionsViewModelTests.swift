// SessionsViewModelTests
//
// BDD-named tests for Settings ▸ Security (work-consolidation.md G19).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class SessionsViewModelTests: XCTestCase {

    private func session(
        _ id: String,
        label: String = "Mac",
        isCurrent: Bool = false,
        lastUsed: Date? = nil
    ) -> ActiveSession {
        ActiveSession(id: id, deviceLabel: label, lastUsedAt: lastUsed, isCurrent: isCurrent)
    }

    // MARK: - Happy path

    func test_givenSessions_whenLoading_thenOrdersCurrentFirstThenMostRecent() async {
        let stub = StubSessionsService()
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 9_000)
        stub.enqueueSessions(success: [
            session("a", label: "Old", lastUsed: old),
            session("b", label: "Recent", lastUsed: recent),
            session("c", label: "This Mac", isCurrent: true, lastUsed: old)
        ])
        let viewModel = SessionsViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.sessions.map(\.id), ["c", "b", "a"])
        XCTAssertNil(viewModel.error)
    }

    func test_givenSession_whenRevoking_thenRemovesItAndCallsService() async {
        let stub = StubSessionsService()
        stub.enqueueSessions(success: [session("a"), session("b")])
        stub.enqueueRevoke()
        let viewModel = SessionsViewModel(service: stub)
        await viewModel.load()

        await viewModel.revoke(session("a"))

        XCTAssertEqual(viewModel.sessions.map(\.id), ["b"])
        XCTAssertEqual(stub.revokedIDs, ["a"])
        XCTAssertNil(viewModel.revokingID)
    }

    // MARK: - Invalid / unavailable

    func test_givenNoService_whenLoading_thenReportsUnavailableAndDoesNothing() async {
        let viewModel = SessionsViewModel(service: nil)

        await viewModel.load()

        XCTAssertTrue(viewModel.isUnavailable)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Upstream failure

    func test_givenLoadFailure_whenLoading_thenSurfacesErrorRatherThanEmptyList() async {
        let stub = StubSessionsService()
        stub.enqueueSessions(failure: URLError(.notConnectedToInternet))
        let viewModel = SessionsViewModel(service: stub)

        await viewModel.load()

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.sessions.isEmpty)
    }

    func test_givenRevokeFailure_whenRevoking_thenKeepsRowAndSurfacesError() async {
        let stub = StubSessionsService()
        stub.enqueueSessions(success: [session("a")])
        stub.enqueueRevoke(failure: URLError(.badServerResponse))
        let viewModel = SessionsViewModel(service: stub)
        await viewModel.load()

        await viewModel.revoke(session("a"))

        // The row must survive a failed revoke — showing it gone would imply a
        // revocation that never happened.
        XCTAssertEqual(viewModel.sessions.map(\.id), ["a"])
        XCTAssertNotNil(viewModel.error)
    }

    // MARK: - Empty / boundary

    func test_givenNoSessions_whenLoading_thenListIsEmptyWithoutError() async {
        let stub = StubSessionsService()
        stub.enqueueSessions(success: [])
        let viewModel = SessionsViewModel(service: stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNil(viewModel.error)
    }
}
