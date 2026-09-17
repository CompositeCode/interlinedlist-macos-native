import XCTest
@testable import InterlinedDomain

/// BDD-named coverage for `ViewingPreference` — the domain projection of
/// `UserDTO.viewingPreference` (work-consolidation.md G35 / issue #43).
///
/// The wire vocabulary asserted here was read off the live web Settings form on
/// 2026-09-09 (`<select id="viewingPreference">`), not guessed, so these cases
/// double as a contract record: if the server ever renames a token, the
/// round-trip test is what will notice.
final class ViewingPreferenceTests: XCTestCase {

    // MARK: - Happy path

    func test_givenDocumentedTokens_whenDecoding_thenMapsToTypedCases() {
        XCTAssertEqual(ViewingPreference(wireToken: "my_messages"), .myMessages)
        XCTAssertEqual(ViewingPreference(wireToken: "all_messages"), .allMessages)
        XCTAssertEqual(ViewingPreference(wireToken: "followers_only"), .followersOnly)
        XCTAssertEqual(ViewingPreference(wireToken: "following_only"), .followingOnly)
    }

    func test_givenTypedCases_whenEncoding_thenProducesTheDocumentedTokens() {
        XCTAssertEqual(ViewingPreference.myMessages.wireToken, "my_messages")
        XCTAssertEqual(ViewingPreference.allMessages.wireToken, "all_messages")
        XCTAssertEqual(ViewingPreference.followersOnly.wireToken, "followers_only")
        XCTAssertEqual(ViewingPreference.followingOnly.wireToken, "following_only")
    }

    func test_givenEachSelectableValue_whenResolvingScope_thenPicksTheMatchingFeed() {
        XCTAssertEqual(ViewingPreference.myMessages.defaultScope, .mine)
        XCTAssertEqual(ViewingPreference.allMessages.defaultScope, .all)
        XCTAssertEqual(ViewingPreference.followersOnly.defaultScope, .followers)
        XCTAssertEqual(ViewingPreference.followingOnly.defaultScope, .following)
    }

    func test_givenSelectableList_whenOfferedToTheUser_thenMatchesTheWebFormsOptions() {
        XCTAssertEqual(
            ViewingPreference.selectable.map(\.wireToken),
            ["my_messages", "all_messages", "followers_only", "following_only"]
        )
        XCTAssertEqual(
            ViewingPreference.selectable.map(\.displayName),
            ["My Messages", "All Messages", "Followers Only", "Following Only"]
        )
    }

    // MARK: - Invalid input

    func test_givenUnrecognisedToken_whenDecoding_thenPreservesItAndDefaultsToAll() {
        let preference = ViewingPreference(wireToken: "mentions_only")

        XCTAssertEqual(preference, .other("mentions_only"))
        XCTAssertEqual(preference.defaultScope, .all, "An unknown filter must not blank the feed")
        XCTAssertEqual(preference.wireToken, "mentions_only", "The token must survive a round-trip")
        XCTAssertFalse(
            ViewingPreference.selectable.contains(preference),
            "An unknown token is never offered as a choice"
        )
    }

    // MARK: - Upstream / backend availability

    /// Re-verified live 2026-09-09: `GET /api/messages` honours only
    /// `onlyMine`; every follower-filter parameter returns the full timeline.
    /// So both follower feeds must report themselves unavailable, which is what
    /// drives the timeline's "coming soon" state instead of a mislabelled feed.
    func test_givenFollowerPreferences_whenCheckingBackendSupport_thenReportsUnavailable() {
        XCTAssertFalse(ViewingPreference.followersOnly.hasBackendFeed)
        XCTAssertFalse(ViewingPreference.followingOnly.hasBackendFeed)
        XCTAssertFalse(TimelineScope.followers.hasBackendFeed)
        XCTAssertFalse(TimelineScope.following.hasBackendFeed)

        XCTAssertTrue(ViewingPreference.myMessages.hasBackendFeed)
        XCTAssertTrue(ViewingPreference.allMessages.hasBackendFeed)
        XCTAssertTrue(TimelineScope.all.hasBackendFeed)
        XCTAssertTrue(TimelineScope.mine.hasBackendFeed)
    }

    // MARK: - Boundary

    func test_givenBlankToken_whenDecoding_thenTreatsItAsUnrecognisedRatherThanCrashing() {
        // Whitespace-only and empty tokens are boundary inputs the server has
        // never sent but could; they must degrade to the safe `.all` scope.
        XCTAssertEqual(ViewingPreference(wireToken: "").defaultScope, .all)
        XCTAssertEqual(ViewingPreference(wireToken: "   ").defaultScope, .all)
        XCTAssertEqual(ViewingPreference(wireToken: "   ").wireToken, "")
    }

    func test_givenPaddedToken_whenDecoding_thenTrimsBeforeMatching() {
        // The trim exists so a stray newline in a payload doesn't demote a
        // perfectly good preference to `.other`.
        XCTAssertEqual(ViewingPreference(wireToken: " following_only\n"), .followingOnly)
    }
}
