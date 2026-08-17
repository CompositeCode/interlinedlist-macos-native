import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `ModerationService` (work-consolidation.md G2). Quartet per
/// public method: happy + invalid + failure + empty/boundary.
final class ModerationServiceTests: XCTestCase {

    // MARK: - blockedUsers

    func test_givenBlockedUsers_whenLoading_thenMapsRowsAndHitsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"blockedUsers":[{"id":"u1","username":"spammer","displayName":"Spam","avatar":"https://cdn/x.png"}],
         "pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}
        """#)
        let service = ModerationService(api: api)

        let users = try await service.blockedUsers()

        XCTAssertEqual(users.map(\.id), ["u1"])
        XCTAssertEqual(users.first?.username, "spammer")
        XCTAssertEqual(users.first?.avatarURL?.absoluteString, "https://cdn/x.png")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "GET")
        XCTAssertEqual(recorded.first?.path, "/api/user/blocks")
    }

    func test_givenServerFailure_whenLoadingBlocked_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = ModerationService(api: api)

        do {
            _ = try await service.blockedUsers()
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenNoBlocked_whenLoading_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"blockedUsers":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}"#)
        let service = ModerationService(api: api)

        let users = try await service.blockedUsers()

        XCTAssertTrue(users.isEmpty)
    }

    // MARK: - mutedUsers

    func test_givenMutedUsers_whenLoading_thenMapsRowsAndHitsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"mutedUsers":[{"id":"u2"}],"pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}"#)
        let service = ModerationService(api: api)

        let users = try await service.mutedUsers()

        XCTAssertEqual(users.map(\.id), ["u2"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/mutes")
    }

    // MARK: - block / unblock / mute / unmute

    func test_givenUsername_whenBlocking_thenPostsToBlockPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"ok":true}"#)
        let service = ModerationService(api: api)

        try await service.block(username: "ada")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/users/ada/block")
    }

    func test_givenUsername_whenUnblocking_thenDeletesBlockPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{}"#)
        let service = ModerationService(api: api)

        try await service.unblock(username: "ada")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/users/ada/block")
    }

    func test_givenUsername_whenMuting_thenPostsToMutePath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{}"#)
        let service = ModerationService(api: api)

        try await service.mute(username: "ada")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/users/ada/mute")
        XCTAssertEqual(recorded.first?.method, "POST")
    }

    func test_givenBlockFails_whenBlocking_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "cannot block yourself"))
        let service = ModerationService(api: api)

        do {
            try await service.block(username: "me")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "cannot block yourself"))
        }
    }

    // MARK: - reporting

    func test_givenReason_whenReportingUser_thenPostsToReportPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"ok":true}"#)
        let service = ModerationService(api: api)

        try await service.reportUser(username: "ada", reason: .spam, detail: "  ")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/users/ada/report")
    }

    func test_givenReason_whenReportingMessage_thenPostsToMessageReportPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"ok":true}"#)
        let service = ModerationService(api: api)

        try await service.reportMessage(id: "m1", reason: .harassment)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/messages/m1/report")
    }

    // MARK: - isBlocking (derived)

    func test_givenUserInBlockList_whenCheckingIsBlocking_thenTrue() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"blockedUsers":[{"id":"u1","username":"Spammer"}],"pagination":{"total":1,"limit":100,"offset":0,"hasMore":false}}"#)
        let service = ModerationService(api: api)

        let blocking = try await service.isBlocking(username: "spammer") // case-insensitive

        XCTAssertTrue(blocking)
    }

    func test_givenUserNotInBlockList_whenCheckingIsBlocking_thenFalse() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"blockedUsers":[],"pagination":{"total":0,"limit":100,"offset":0,"hasMore":false}}"#)
        let service = ModerationService(api: api)

        let blocking = try await service.isBlocking(username: "ghost")

        XCTAssertFalse(blocking)
    }

    // MARK: - ReportReason

    func test_givenReportReason_whenReadingRawValues_thenMatchAPIContract() {
        XCTAssertEqual(ReportReason.allCases.map(\.rawValue),
                       ["harassment", "spam", "misinformation", "inappropriate", "other"])
        XCTAssertEqual(ReportReason.inappropriate.label, "Inappropriate content")
    }
}
