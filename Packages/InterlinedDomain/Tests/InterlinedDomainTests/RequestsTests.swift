import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `SocialService.requests()` and the underlying
/// `FollowRequest` domain projection (PLAN.md §1 "Follow system / request
/// approval for private accounts", §6 M5, §7 testing). The envelope shape
/// was pinned by the 2026-06-24 live probe — `{ requests: [...] }`, no
/// pagination wrapper (Wave 1 deviation 5 closure).
final class RequestsTests: XCTestCase {

    // MARK: - Happy path

    func test_givenPendingRequests_whenLoadingRequests_thenMapsEveryRow() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followRequestsEnvelope(ids: ["u-1", "u-2"]))
        let service = SocialService(api: api)

        // When
        let requests = try await service.requests()

        // Then
        XCTAssertEqual(requests.map(\.id), ["f-u-1", "f-u-2"])
        XCTAssertEqual(requests.map(\.user.id), ["u-1", "u-2"])
        XCTAssertEqual(requests.first?.user.displayName, "Ada Lovelace")
        XCTAssertEqual(
            requests.first?.user.avatarURL?.absoluteString,
            "https://cdn.interlinedlist.com/ada.png"
        )
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "GET")
        XCTAssertEqual(recorded.first?.path, "/api/follow/requests")
    }

    // MARK: - Invalid input — wrong shape

    func test_givenMalformedEnvelope_whenLoadingRequests_thenThrowsDecoding() async throws {
        // Given — bare array, missing the `requests` key.
        let api = StubAPIClient()
        await api.enqueue(json: "[]")
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.requests()
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }

    // MARK: - Upstream failure

    func test_givenRequestsEndpointFails_whenLoadingRequests_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "sign in"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.requests()
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "sign in"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoPendingRequests_whenLoadingRequests_thenReturnsEmptyList() async throws {
        // Given — boundary: empty inbox.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followRequestsEnvelope(ids: []))
        let service = SocialService(api: api)

        // When
        let requests = try await service.requests()

        // Then
        XCTAssertTrue(requests.isEmpty)
    }

    // MARK: - FollowRequest mapper directly

    func test_givenDTOWithFollowId_whenMapping_thenUsesFollowIdAsPrimaryKey() {
        // Given
        let dto = FollowUserDTO(
            id: "user-7",
            username: "ada",
            displayName: "Ada",
            avatar: "https://cdn/x.png",
            followId: "follow-42",
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            status: "pending"
        )

        // When
        let request = FollowRequest(from: dto)

        // Then — the follow row id takes precedence so approve/reject can
        // target the follow record without an extra lookup.
        XCTAssertEqual(request.id, "follow-42")
        XCTAssertEqual(request.user.id, "user-7")
        XCTAssertEqual(request.createdAt, Date(timeIntervalSince1970: 1_000_000))
    }

    func test_givenDTOWithoutFollowId_whenMapping_thenFallsBackToUserId() {
        // Given — server omits `followId` (an edge the wire contract allows).
        let dto = FollowUserDTO(
            id: "user-7",
            username: "ada",
            displayName: "Ada",
            avatar: nil,
            followId: nil,
            createdAt: nil,
            status: "pending"
        )

        // When
        let request = FollowRequest(from: dto)

        // Then
        XCTAssertEqual(request.id, "user-7")
        XCTAssertNil(request.createdAt)
    }

    // MARK: - FollowRelationship mapper directly

    func test_givenStatusDTO_whenMappingRelationship_thenFlagsMapToState() {
        // Following → .following
        let followingDTO = FollowStatusDTO(
            following: true,
            followedBy: true,
            pendingRequest: false
        )
        let following = FollowRelationship(from: followingDTO)
        XCTAssertEqual(following.state, .following)
        XCTAssertTrue(following.isMutual)

        // Pending → .pending
        let pendingDTO = FollowStatusDTO(
            following: false,
            followedBy: false,
            pendingRequest: true
        )
        XCTAssertEqual(FollowRelationship(from: pendingDTO).state, .pending)

        // Nothing → .notFollowing
        let neitherDTO = FollowStatusDTO(
            following: false,
            followedBy: true,
            pendingRequest: false
        )
        let oneWay = FollowRelationship(from: neitherDTO)
        XCTAssertEqual(oneWay.state, .notFollowing)
        XCTAssertFalse(oneWay.isMutual)
    }
}
