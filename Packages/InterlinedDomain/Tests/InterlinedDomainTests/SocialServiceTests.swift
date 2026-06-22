import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `SocialService` (M1 task 1B — PLAN.md §1 "Follow
/// system", §6 M1 read-only surface, §7 testing).
///
/// Minimum coverage per behavior per PLAN.md §7: happy path, invalid input,
/// upstream API failure, and empty/boundary case.
final class SocialServiceTests: XCTestCase {

    // MARK: - status

    func test_givenRelationshipExists_whenLoadingStatus_thenMapsAllFlags() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followStatus(
            following: true,
            followedBy: true,
            pendingRequest: false
        ))
        let service = SocialService(api: api)

        // When
        let status = try await service.status(of: "user-42")

        // Then
        XCTAssertTrue(status.following)
        XCTAssertTrue(status.followedBy)
        XCTAssertFalse(status.pendingRequest)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42/status")
    }

    func test_givenStatusEndpointForbidden_whenLoadingStatus_thenThrows() async throws {
        // Given — invalid input case: a private account the caller cannot see.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "private account"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.status(of: "user-private")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "private account"))
        }
    }

    // MARK: - counts

    func test_givenUserHasFollowers_whenLoadingCounts_thenMapsBothCounts() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followCounts(followerCount: 12, followingCount: 7))
        let service = SocialService(api: api)

        // When
        let counts = try await service.counts(of: "user-42")

        // Then
        XCTAssertEqual(counts.followerCount, 12)
        XCTAssertEqual(counts.followingCount, 7)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42/counts")
    }

    func test_givenBrandNewUser_whenLoadingCounts_thenBothCountsAreZero() async throws {
        // Given — boundary: account with no follow relationships yet.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followCounts(followerCount: 0, followingCount: 0))
        let service = SocialService(api: api)

        // When
        let counts = try await service.counts(of: "user-new")

        // Then
        XCTAssertEqual(counts.followerCount, 0)
        XCTAssertEqual(counts.followingCount, 0)
    }

    func test_givenCountsEndpointFails_whenLoadingCounts_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.counts(of: "user-42")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport(message: "offline"))
        }
    }

    // MARK: - followers

    func test_givenFollowers_whenLoadingFollowers_thenMapsUserSummaries() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followUserArray(ids: ["u-1", "u-2"]))
        let service = SocialService(api: api)

        // When
        let page = try await service.followers(of: "user-42", limit: 20, offset: 0)

        // Then
        XCTAssertEqual(page.users.map(\.id), ["u-1", "u-2"])
        XCTAssertEqual(page.users.first?.displayName, "Ada Lovelace")
        XCTAssertEqual(page.users.first?.avatarURL?.absoluteString, "https://cdn.interlinedlist.com/ada.png")
        // Bare-array shape: cursor fields default to "no more".
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42/followers")
    }

    func test_givenNoFollowers_whenLoadingFollowers_thenReturnsEmptyPage() async throws {
        // Given — boundary: nobody follows this account.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followUserArray(ids: []))
        let service = SocialService(api: api)

        // When
        let page = try await service.followers(of: "user-lonely", limit: 20, offset: 0)

        // Then
        XCTAssertTrue(page.users.isEmpty)
        XCTAssertFalse(page.hasMore)
    }

    func test_givenFollowersEndpointFails_whenLoadingFollowers_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "sign in"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.followers(of: "user-42", limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "sign in"))
        }
    }

    // MARK: - following

    func test_givenFollowing_whenLoadingFollowing_thenMapsUserSummaries() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followUserArray(ids: ["u-3"]))
        let service = SocialService(api: api)

        // When
        let page = try await service.following(of: "user-42", limit: 20, offset: 0)

        // Then
        XCTAssertEqual(page.users.map(\.id), ["u-3"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42/following")
    }

    func test_givenFollowingEndpointFails_whenLoadingFollowing_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "bad id"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.following(of: "", limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "bad id"))
        }
    }

    // MARK: - profile (decision 0002 — public-profile fallback)

    func test_givenUsernameWithMessages_whenLoadingProfile_thenMapsEmbeddedUser() async throws {
        // Given — the username's public-messages feed has at least one entry,
        // so the embedded author is available to project from.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["m-1"]))
        let service = SocialService(api: api)

        // When
        let profile = try await service.profile(username: "ada")

        // Then — identity stitched from the embedded `user` block.
        XCTAssertEqual(profile.id, "user-ada")
        XCTAssertEqual(profile.username, "ada")
        XCTAssertEqual(profile.displayName, "Ada Lovelace")
        XCTAssertEqual(profile.avatarURL?.absoluteString, "https://cdn.interlinedlist.com/ada.png")

        // And — request shape: tiny page (limit 1, offset 0), no full feed pull.
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/ada/messages")
        XCTAssertEqual(recorded.first?.query["limit"], "1")
        XCTAssertEqual(recorded.first?.query["offset"], "0")
    }

    func test_givenUsernameWithMessages_whenLoadingProfile_thenRicherFieldsAreNilForM1() async throws {
        // Given — happy path again, but asserting the M1 limitation is
        // encoded as a test rather than a hidden assumption: the fallback
        // cannot populate bio/counts/joinedAt, so they must be `nil`.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["m-1"]))
        let service = SocialService(api: api)

        // When
        let profile = try await service.profile(username: "ada")

        // Then
        XCTAssertNil(profile.bio)
        XCTAssertNil(profile.followerCount)
        XCTAssertNil(profile.followingCount)
        XCTAssertNil(profile.joinedAt)
        XCTAssertFalse(profile.isPrivate)
    }

    func test_givenUsernameWithNoMessages_whenLoadingProfile_thenThrowsProfileUnavailable() async throws {
        // Given — boundary / empty path: zero public messages means no
        // embedded author to project from.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: []))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.profile(username: "ghost")
            XCTFail("Expected SocialError.profileUnavailable")
        } catch let error as SocialError {
            XCTAssertEqual(error, .profileUnavailable(username: "ghost"))
        }
    }

    func test_givenAPIReturns404_whenLoadingProfile_thenThrowsAPIError() async throws {
        // Given — upstream API failure: username does not exist.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "user not found"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.profile(username: "nobody")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "user not found"))
        }
    }

    func test_givenAPIReturnsMalformedPayload_whenLoadingProfile_thenThrowsDecoding() async throws {
        // Given — invalid input case: response missing the `messages`
        // collection key. `PaginatedDecoder` surfaces this as `.decoding`.
        let api = StubAPIClient()
        await api.enqueue(json: "{ \"oops\": [] }")
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.profile(username: "ada")
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            if case .decoding = error {
                // pass — exact decoder message is not part of the contract.
            } else {
                XCTFail("Expected .decoding, got \(error)")
            }
        }
    }
}
