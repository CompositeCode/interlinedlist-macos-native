import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the M5 write surface on `SocialService` (PLAN.md
/// §1 "Follow system", §6 M5, §7 testing). Mirror of the Wave 3 write-test
/// quartet style used by `MessagesServiceTests`: happy + invalid + failure +
/// empty/boundary per method.
final class SocialServiceWriteTests: XCTestCase {

    // MARK: - follow (public account → approved)

    func test_givenPublicTarget_whenFollowing_thenReturnsApproved() async throws {
        // Given — the follow action succeeds and the subsequent status read
        // reports `following: true`, so the typed outcome is `.approved`.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(success: true))
        await api.enqueue(json: Fixtures.followStatus(
            following: true,
            followedBy: false,
            pendingRequest: false
        ))
        let service = SocialService(api: api)

        // When
        let action = try await service.follow(userId: "user-42")

        // Then
        XCTAssertEqual(action, .approved)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.map(\.method), ["POST", "GET"])
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42")
        XCTAssertEqual(recorded.last?.path, "/api/follow/user-42/status")
    }

    func test_givenPrivateTarget_whenFollowing_thenReturnsPending() async throws {
        // Given — boundary case: the action succeeded but the relationship
        // status reads `pendingRequest: true`, not `following`.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(success: true))
        await api.enqueue(json: Fixtures.followStatus(
            following: false,
            followedBy: false,
            pendingRequest: true
        ))
        let service = SocialService(api: api)

        // When
        let action = try await service.follow(userId: "user-private")

        // Then
        XCTAssertEqual(action, .pending)
    }

    func test_givenLagBetweenActionAndStatus_whenFollowing_thenDefaultsToPending() async throws {
        // Given — invalid input / eventual-consistency window: the action
        // accepted but the status snapshot returns neither flag set. The
        // defensive default is `.pending` (the UI shows "Requested" until
        // the next refresh).
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(success: true))
        await api.enqueue(json: Fixtures.followStatus(
            following: false,
            followedBy: false,
            pendingRequest: false
        ))
        let service = SocialService(api: api)

        // When
        let action = try await service.follow(userId: "user-lag")

        // Then
        XCTAssertEqual(action, .pending)
    }

    func test_givenFollowActionFails_whenFollowing_thenThrowsAndSkipsStatusRead() async throws {
        // Given — upstream API failure on the write itself; the service
        // must not call status.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "blocked"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.follow(userId: "user-blocked")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "blocked"))
        }
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1, "Status should not be called after a failed action")
    }

    // MARK: - unfollow

    func test_givenFollowedTarget_whenUnfollowing_thenSucceedsSilently() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(success: true))
        let service = SocialService(api: api)

        // When / Then — no return value; we assert no throw + request shape.
        try await service.unfollow(userId: "user-42")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42")
    }

    func test_givenUnfollowEndpointFails_whenUnfollowing_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = SocialService(api: api)

        // When / Then
        do {
            try await service.unfollow(userId: "user-42")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport(message: "offline"))
        }
    }

    func test_givenEmptyId_whenUnfollowing_thenAPIBadRequestPropagates() async throws {
        // Given — invalid input boundary: empty userId. The kit builder
        // builds the URL; the API rejects with 400 and we propagate.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "missing id"))
        let service = SocialService(api: api)

        // When / Then
        do {
            try await service.unfollow(userId: "")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "missing id"))
        }
    }

    // MARK: - approve

    func test_givenPendingRequest_whenApproving_thenSucceeds() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(success: true))
        let service = SocialService(api: api)

        // When
        try await service.approve(userId: "user-pending")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-pending/approve")
    }

    func test_givenApproveFails_whenApproving_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no such request"))
        let service = SocialService(api: api)

        // When / Then
        do {
            try await service.approve(userId: "user-ghost")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no such request"))
        }
    }

    // MARK: - reject

    func test_givenPendingRequest_whenRejecting_thenSucceeds() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(success: true))
        let service = SocialService(api: api)

        // When
        try await service.reject(userId: "user-pending")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-pending/reject")
    }

    func test_givenRejectFails_whenRejecting_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = SocialService(api: api)

        // When / Then
        do {
            try await service.reject(userId: "user-x")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - removeFollower

    func test_givenFollower_whenRemoving_thenSucceeds() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(success: true))
        let service = SocialService(api: api)

        // When
        try await service.removeFollower(userId: "user-42")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42/remove")
    }

    func test_givenRemoveFollowerFails_whenRemoving_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "sign in"))
        let service = SocialService(api: api)

        // When / Then
        do {
            try await service.removeFollower(userId: "user-42")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "sign in"))
        }
    }
}
