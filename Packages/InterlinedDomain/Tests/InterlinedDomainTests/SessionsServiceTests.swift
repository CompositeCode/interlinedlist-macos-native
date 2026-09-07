import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD coverage for `SessionsService` + the `ActiveSession` mapper
/// (work-consolidation.md G19).
final class SessionsServiceTests: XCTestCase {

    // MARK: - Happy path

    func test_givenSessions_whenFetching_thenMapsEveryFieldAndHitsTheRoute() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "sessions": [
            { "id": "sess_1", "deviceLabel": "MacBook Pro",
              "createdAt": "2026-09-01T10:00:00Z",
              "lastUsedAt": "2026-09-05T18:22:00Z", "isCurrent": true } ] }
        """#)
        let service = SessionsService(api: api)

        let sessions = try await service.sessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "sess_1")
        XCTAssertEqual(sessions[0].deviceLabel, "MacBook Pro")
        XCTAssertTrue(sessions[0].isCurrent)
        XCTAssertNotNil(sessions[0].createdAt)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/sessions")
    }

    func test_givenSessionID_whenRevoking_thenSendsDeleteToThatSession() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = SessionsService(api: api)

        try await service.revoke(sessionID: "sess_9")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/sessions/sess_9")
        XCTAssertEqual(recorded.first?.method, "DELETE")
    }

    // MARK: - Invalid / incomplete input

    func test_givenSessionMissingLabelAndFlag_whenFetching_thenUsesSafeDefaults() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "sessions": [ { "id": "sess_2" } ] }"#)
        let service = SessionsService(api: api)

        let sessions = try await service.sessions()

        // A missing label must still render, and a missing `isCurrent` must not
        // accidentally mark a row as the current session.
        XCTAssertEqual(sessions[0].deviceLabel, "Unknown device")
        XCTAssertFalse(sessions[0].isCurrent)
        XCTAssertNil(sessions[0].lastUsedAt)
    }

    // MARK: - Upstream failure

    func test_givenServerFailure_whenFetching_thenThrows() async {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = SessionsService(api: api)

        do {
            _ = try await service.sessions()
            XCTFail("A security pane must surface the failure, not show a stale list")
        } catch {
            // expected
        }
    }

    func test_givenServerFailure_whenRevoking_thenThrows() async {
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "nope"))
        let service = SessionsService(api: api)

        do {
            try await service.revoke(sessionID: "sess_1")
            XCTFail("Expected the revoke failure to propagate")
        } catch {
            // expected
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoSessions_whenFetching_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "sessions": [] }"#)
        let service = SessionsService(api: api)

        let sessions = try await service.sessions()

        XCTAssertTrue(sessions.isEmpty)
    }
}
