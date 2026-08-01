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
        // Given — wrapped envelope `{ followers, pagination }` (Wave 1
        // deviation 5 closed 2026-06-24).
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followersEnvelope(ids: ["u-1", "u-2"]))
        let service = SocialService(api: api)

        // When
        let page = try await service.followers(of: "user-42", limit: 20, offset: 0)

        // Then
        XCTAssertEqual(page.users.map(\.id), ["u-1", "u-2"])
        XCTAssertEqual(page.users.first?.displayName, "Ada Lovelace")
        XCTAssertEqual(page.users.first?.avatarURL?.absoluteString, "https://cdn.interlinedlist.com/ada.png")
        // Fixture sets hasMore=false; cursor cleared.
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/follow/user-42/followers")
    }

    func test_givenNoFollowers_whenLoadingFollowers_thenReturnsEmptyPage() async throws {
        // Given — boundary: nobody follows this account.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followersEnvelope(ids: []))
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
        // Given — wrapped envelope `{ following, pagination }`.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.followingEnvelope(ids: ["u-3"]))
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

    // MARK: - profile (D2 public endpoint + decision-0002 fallback)

    func test_givenPublicProfileEndpoint_whenLoadingProfile_thenMapsRichProfile() async throws {
        // Given — the dedicated `GET /api/users/{username}` endpoint (D2).
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"id":"user-ada","username":"ada","displayName":"Ada Lovelace",
         "avatar":"https://cdn/ada.png","headerImage":null,"bio":"Countess of Computing",
         "joinedAt":"2026-03-23T23:23:59.755Z","isPrivate":false,
         "followerCount":42,"followingCount":7,"publicMessageCount":10,"publicListCount":2}
        """#)
        let service = SocialService(api: api)

        // When
        let profile = try await service.profile(username: "ada")

        // Then — the rich payload maps straight through (no counts stitch).
        XCTAssertEqual(profile.id, "user-ada")
        XCTAssertEqual(profile.username, "ada")
        XCTAssertEqual(profile.bio, "Countess of Computing")
        XCTAssertEqual(profile.followerCount, 42)
        XCTAssertEqual(profile.followingCount, 7)
        XCTAssertNotNil(profile.joinedAt)

        // And — it hits the public-profile path, not the message fallback.
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.path, "/api/users/ada")
    }

    func test_givenProfileEndpoint404_whenLoadingProfile_thenFallsBackToEmbeddedAuthor() async throws {
        // Given — a pre-migration server that 404s the profile endpoint; the
        // decision-0002 fallback derives identity from the embedded author.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no profile endpoint"))
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["m-1"]))
        let service = SocialService(api: api)

        // When
        let profile = try await service.profile(username: "ada")

        // Then — identity stitched from the embedded `user` block.
        XCTAssertEqual(profile.id, "user-ada")
        XCTAssertEqual(profile.username, "ada")
        XCTAssertEqual(profile.displayName, "Ada Lovelace")

        // And — the fallback hit the tiny public-messages page.
        let recorded = await api.recorded
        XCTAssertEqual(recorded.last?.path, "/api/user/ada/messages")
        XCTAssertEqual(recorded.last?.query["limit"], "1")
    }

    func test_givenFallbackAuthor_whenLoadingProfile_thenRicherFieldsAreNil() async throws {
        // Given — the fallback path cannot populate bio/counts/joinedAt.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no profile endpoint"))
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

    func test_givenFallbackWithNoMessages_whenLoadingProfile_thenThrowsProfileUnavailable() async throws {
        // Given — endpoint 404s AND the user has zero public messages.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no profile endpoint"))
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

    func test_givenProfileEndpointServerError_whenLoadingProfile_thenThrowsWithoutFallback() async throws {
        // Given — a non-404 failure must propagate, not trigger the fallback.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = SocialService(api: api)

        // When / Then
        do {
            _ = try await service.profile(username: "nobody")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
        // And — no fallback message call was made.
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.path, "/api/users/nobody")
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
