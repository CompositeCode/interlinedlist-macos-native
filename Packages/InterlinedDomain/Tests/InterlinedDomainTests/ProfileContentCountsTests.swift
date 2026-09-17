// ProfileContentCountsTests
//
// The content counts on a public profile (GitHub #44 / G32).
//
// `GET /api/users/{username}` has always returned `publicMessageCount` and
// `publicListCount`, and `PublicProfileDTO` has always decoded them — they were
// dropped at the **domain** boundary, so the profile header could only ever show
// two of the web's five stat tiles. These tests pin the carry-through, including
// the place it is easiest to lose: the follow-counts stitch.

import XCTest
@testable import InterlinedDomain
@testable import InterlinedKit

final class ProfileContentCountsTests: XCTestCase {

    /// The live payload, captured 2026-09-15 from the test account.
    private let profileJSON = """
    {
      "id": "15e3d575-98bc-40e5-9aba-0d9cc9e30799",
      "username": "messenger",
      "displayName": "Messenger & Recon @ InterlinedList",
      "avatar": "https://example.com/avatar.jpg",
      "headerImage": null,
      "bio": "Post it once, send it everywhere.",
      "joinedAt": "2026-03-23T23:23:59.755Z",
      "isPrivate": false,
      "followerCount": 1,
      "followingCount": 1,
      "publicMessageCount": 31,
      "publicListCount": 0
    }
    """

    // MARK: - Happy path

    func test_givenTheLiveProfilePayload_whenMapping_thenTheContentCountsSurvive() throws {
        let dto = try JSONCoders.makeDecoder().decode(
            PublicProfileDTO.self,
            from: Data(profileJSON.utf8)
        )

        let profile = UserProfile(from: dto)

        XCTAssertEqual(profile.publicMessageCount, 31)
        XCTAssertEqual(profile.publicListCount, 0)
        XCTAssertEqual(profile.followerCount, 1)
        XCTAssertEqual(profile.followingCount, 1)
    }

    // MARK: - The stitch must not blank them

    func test_givenAFollowCountsStitch_whenApplied_thenTheContentCountsAreCarriedThrough() throws {
        // `withCounts` exists to refresh followers/following from the dedicated
        // counts call. Rebuilding the profile without carrying the content
        // counts would blank two tiles every time that follow-up landed — a
        // regression that would look like flicker, not like a bug.
        let dto = try JSONCoders.makeDecoder().decode(
            PublicProfileDTO.self,
            from: Data(profileJSON.utf8)
        )
        let profile = UserProfile(from: dto)

        let stitched = profile.withCounts(FollowCounts(followers: 9, following: 8))

        XCTAssertEqual(stitched.followerCount, 9, "the stitch is what refreshes these")
        XCTAssertEqual(stitched.followingCount, 8)
        XCTAssertEqual(stitched.publicMessageCount, 31, "and must not blank these on the way past")
        XCTAssertEqual(stitched.publicListCount, 0)
    }

    // MARK: - Boundary — absent is not zero

    func test_givenAPayloadWithoutCounts_whenMapping_thenTheyAreNilNotZero() throws {
        // "0 posts" and "we could not find out how many posts" look identical
        // and mean opposite things. A tile is omitted for `nil`, so the
        // distinction has to survive mapping.
        let json = """
        { "id": "u1", "username": "ada" }
        """
        let dto = try JSONCoders.makeDecoder().decode(PublicProfileDTO.self, from: Data(json.utf8))

        let profile = UserProfile(from: dto)

        XCTAssertNil(profile.publicMessageCount)
        XCTAssertNil(profile.publicListCount)
        XCTAssertNil(profile.headerImageURL)
    }

    // MARK: - Invalid — the reduced-scope fallback knows none of this

    func test_givenTheEmbeddedAuthorFallback_whenMapping_thenContentCountsAreNil() {
        // Decision 0002's fallback projects identity from a message's author and
        // genuinely cannot know these. Defaulting them to zero there would
        // publish a confident wrong number.
        let json = """
        {
          "id": "m1", "content": "hi", "publiclyVisible": true,
          "userId": "u1",
          "createdAt": "2026-09-15T10:00:00.000Z",
          "updatedAt": "2026-09-15T10:00:00.000Z",
          "digCount": 0, "pushCount": 0, "dugByMe": false,
          "user": {"id":"u1","username":"ada","displayName":"Ada","avatar":null}
        }
        """
        let message = try! JSONCoders.makeDecoder().decode(MessageDTO.self, from: Data(json.utf8))

        let profile = UserProfile(fromEmbeddedAuthorOf: message)

        XCTAssertNil(profile.publicMessageCount)
        XCTAssertNil(profile.publicListCount)
    }
}
