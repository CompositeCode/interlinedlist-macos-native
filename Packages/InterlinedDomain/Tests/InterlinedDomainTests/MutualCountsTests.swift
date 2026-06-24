import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `SocialService.mutual(of:)` and the underlying
/// `MutualCounts` domain projection (PLAN.md §1 "Follow system / mutuals",
/// §6 M5, §7 testing). The endpoint shape was pinned by the 2026-06-24 live
/// probe — `{ mutualFollowers, mutualFollowing }`, counts only (Wave 1
/// deviation 5 closure).
final class MutualCountsTests: XCTestCase {

    // MARK: - Happy path

    func test_givenMutualOverlap_whenLoadingMutual_thenMapsBothCounts() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.mutualCountsEnvelope(
            mutualFollowers: 12,
            mutualFollowing: 5
        ))
        let service = SocialService(api: api)

        // When
        let counts = try await service.mutual(of: "user-42")

        // Then
        XCTAssertEqual(counts.mutualFollowers, 12)
        XCTAssertEqual(counts.mutualFollowing, 5)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42/mutual")
    }

    // MARK: - Invalid input

    func test_givenMalformedEnvelope_whenLoadingMutual_thenThrowsDecoding() async throws {
        // Given — wrong shape: list, not counts. The decoder must reject.
        let api = StubAPIClient()
        await api.enqueue(json: "[]")
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.mutual(of: "user-42")
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }

    // MARK: - Upstream failure

    func test_givenMutualEndpointFails_whenLoadingMutual_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "private account"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.mutual(of: "user-private")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "private account"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoOverlap_whenLoadingMutual_thenBothCountsAreZero() async throws {
        // Given — boundary: brand-new account, zero overlap.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.mutualCountsEnvelope(
            mutualFollowers: 0,
            mutualFollowing: 0
        ))
        let service = SocialService(api: api)

        // When
        let counts = try await service.mutual(of: "user-new")

        // Then
        XCTAssertEqual(counts, .zero)
    }

    // MARK: - Direct DTO → domain projection

    func test_givenDTO_whenMappingMutualCounts_thenLosslessRoundTrip() {
        // Given
        let dto = FollowMutualCountsDTO(mutualFollowers: 7, mutualFollowing: 3)

        // When
        let value = MutualCounts(from: dto)

        // Then
        XCTAssertEqual(value.mutualFollowers, 7)
        XCTAssertEqual(value.mutualFollowing, 3)
    }
}
