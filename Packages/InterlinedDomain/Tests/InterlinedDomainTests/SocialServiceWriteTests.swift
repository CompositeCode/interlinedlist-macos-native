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
        // Given — the action response carries `{ "follow": { "status": "active" } }`,
        // which maps directly to `.approved` without a follow-up status read.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(status: "active"))
        let service = SocialService(api: api)

        // When
        let action = try await service.follow(userId: "user-42")

        // Then
        XCTAssertEqual(action, .approved)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.map(\.method), ["POST"])
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42")
    }

    func test_givenPrivateTarget_whenFollowing_thenReturnsPending() async throws {
        // Given — the action response carries `{ "follow": { "status": "pending" } }`,
        // which means the target is a private account awaiting approval.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse(status: "pending"))
        let service = SocialService(api: api)

        // When
        let action = try await service.follow(userId: "user-private")

        // Then
        XCTAssertEqual(action, .pending)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1, "No follow-up status read expected")
    }

    func test_givenActionResponseMissingFollowKey_whenFollowing_thenDefaultsToPending() async throws {
        // Given — boundary / eventual-consistency window: the action accepted
        // but the response body omits the "follow" key entirely. The domain
        // mapper treats `follow: nil` as `.pending` (the safe conservative
        // default — the UI shows "Requested" until the next refresh).
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionEmpty)
        let service = SocialService(api: api)

        // When
        let action = try await service.follow(userId: "user-lag")

        // Then
        XCTAssertEqual(action, .pending)
    }

    func test_givenFollowActionFails_whenFollowing_thenThrowsWithSingleRequest() async throws {
        // Given — upstream API failure on the write itself; only one request
        // is ever made (the POST), no follow-up calls.
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
        XCTAssertEqual(recorded.count, 1, "Only the failed POST is recorded")
    }

    // MARK: - unfollow

    func test_givenFollowedTarget_whenUnfollowing_thenSucceedsSilently() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followActionResponse())
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
        await api.enqueue(json: Fixtures.followActionResponse())
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
        await api.enqueue(json: Fixtures.followActionResponse())
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
        await api.enqueue(json: Fixtures.followActionResponse())
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
