// ProfileViewModelTests
//
// BDD-named tests for the My Profile work (GitHub #44 / G32): landing on the
// signed-in user's own profile, the guard that keeps `profileUnavailable` off
// it, and handle normalisation.
//
// The M1/M5 behaviours of this view model — the counts and mutual follow-ups,
// follow-button configuration — are covered by `ProfileHeaderViewModelTests`.

import XCTest
import InterlinedDomain
@testable import InterlinedList

// MARK: - My Profile (GitHub #44 / G32)
//
// Two behaviours, and the second is the one with teeth.
//
// Landing on your own profile is the feature: the session already knows who the
// user is, so opening Profile to an "enter a username" prompt made the one
// profile everybody wants to see the one that took the most typing to reach.
//
// The guard is that `profileUnavailable` must **never** fire for your own
// account. That state means "this user has no public messages, so there is
// nothing to project a profile from" — a statement about other people's public
// content. Shown for yourself, it tells a brand-new user with nothing posted yet
// that their own profile does not exist.

@MainActor
final class ProfileViewModelTests: XCTestCase {

    /// A profile fixture with the content counts the live payload carries —
    /// `publicMessageCount` and `publicListCount` were decoded by the kit and
    /// dropped at the domain boundary before this work (GitHub #44).
    static func profileFixture(id: String, username: String) -> UserProfile {
        UserProfile(
            summary: UserSummary(id: id, username: username, displayName: username, avatarURL: nil),
            bio: "A bio",
            followerCount: 1,
            followingCount: 1,
            publicMessageCount: 31,
            publicListCount: 2
        )
    }


    // Happy path

    func test_givenASignedInUser_whenTheProfileOpens_thenTheirOwnProfileLoads() async {
        let social = StubSocialService()
        await social.enqueueProfile(success: Self.profileFixture(id: "u-self", username: "ada"))
        await social.enqueueCounts(success: FollowCounts(followers: 3, following: 4))
        let viewModel = ProfileViewModel(
            social: social,
            relationshipReader: StubFollowRelationshipReader(),
            currentUserID: { "u-self" },
            currentUsername: { "ada" }
        )

        await viewModel.loadOwnProfileIfNeeded()

        XCTAssertEqual(viewModel.loadedUsername, "ada")
        XCTAssertEqual(viewModel.profile?.id, "u-self")
        XCTAssertTrue(viewModel.isOwnProfile)
        XCTAssertTrue(viewModel.isSignedIn)
    }

    // Invalid / absent session

    func test_givenNoSession_whenTheProfileOpens_thenNothingIsLoaded() async {
        let social = StubSocialService()
        let viewModel = ProfileViewModel(
            social: social,
            relationshipReader: StubFollowRelationshipReader(),
            currentUserID: { nil },
            currentUsername: { nil }
        )

        await viewModel.loadOwnProfileIfNeeded()

        XCTAssertNil(viewModel.loadedUsername)
        XCTAssertFalse(viewModel.isSignedIn)
        let recorded = await social.recorded
        XCTAssertTrue(recorded.isEmpty, "signed out, there is no own profile to ask for")
    }

    func test_givenAProfileAlreadyBrowsed_whenTheViewReappears_thenItIsNotYankedBack() async {
        // Re-entering the tab must not pull the user off whoever they were
        // looking at.
        let social = StubSocialService()
        await social.enqueueProfile(success: Self.profileFixture(id: "u-other", username: "bob"))
        await social.enqueueCounts(success: FollowCounts(followers: 0, following: 0))
        let viewModel = ProfileViewModel(
            social: social,
            relationshipReader: StubFollowRelationshipReader(),
            currentUserID: { "u-self" },
            currentUsername: { "ada" }
        )
        await viewModel.loadProfile(username: "bob")

        await viewModel.loadOwnProfileIfNeeded()

        XCTAssertEqual(viewModel.loadedUsername, "bob")
        XCTAssertFalse(viewModel.isOwnProfile)
    }

    // Upstream failure — the guard

    func test_givenOwnProfileUnavailable_whenLoading_thenTheEmptyStateIsSuppressed() async {
        // A new account with nothing posted must not be told its own profile
        // does not exist.
        let social = StubSocialService()
        await social.enqueueProfile(failure: SocialError.profileUnavailable(username: "ada"))
        let viewModel = ProfileViewModel(
            social: social,
            relationshipReader: StubFollowRelationshipReader(),
            currentUserID: { "u-self" },
            currentUsername: { "ada" }
        )

        await viewModel.loadProfile(username: "ada")

        XCTAssertNil(viewModel.error, "profileUnavailable can never fire for your own account")
    }

    func test_givenSomeoneElsesProfileUnavailable_whenLoading_thenTheEmptyStateStillFires() async {
        // The other direction: suppressing it universally would hide a real,
        // accurate explanation for someone else's empty profile.
        let social = StubSocialService()
        await social.enqueueProfile(failure: SocialError.profileUnavailable(username: "bob"))
        let viewModel = ProfileViewModel(
            social: social,
            relationshipReader: StubFollowRelationshipReader(),
            currentUserID: { "u-self" },
            currentUsername: { "ada" }
        )

        await viewModel.loadProfile(username: "bob")

        guard case SocialError.profileUnavailable? = viewModel.error as? SocialError else {
            return XCTFail("expected profileUnavailable, got \(String(describing: viewModel.error))")
        }
    }

    // Boundary — handle normalisation

    func test_givenMixedCaseAndAtPrefixedHandles_whenNormalising_thenTheyResolveTheSame() {
        // Handles are case-insensitive on the site (`/user/adron` == `/user/Adron`)
        // and `/@username` is a documented shortcut, so a deep link in any of
        // these forms has to land.
        XCTAssertEqual(ProfileViewModel.normalizedHandle("Adron"), "adron")
        XCTAssertEqual(ProfileViewModel.normalizedHandle("@Adron"), "adron")
        XCTAssertEqual(ProfileViewModel.normalizedHandle("  @ADRON  "), "adron")
        XCTAssertEqual(ProfileViewModel.normalizedHandle("adron"), "adron")
        // Legal username punctuation is passed through untouched rather than
        // sanitised against a charset the client would only get subtly wrong.
        XCTAssertEqual(ProfileViewModel.normalizedHandle("@a.b-c_d"), "a.b-c_d")
        XCTAssertEqual(ProfileViewModel.normalizedHandle("@"), "")
    }

    func test_givenAnAtPrefixedHandle_whenLoading_thenTheNormalisedFormIsRequested() async {
        let social = StubSocialService()
        await social.enqueueProfile(success: Self.profileFixture(id: "u-1", username: "ada"))
        await social.enqueueCounts(success: FollowCounts(followers: 0, following: 0))
        let viewModel = ProfileViewModel(
            social: social,
            relationshipReader: StubFollowRelationshipReader(),
            currentUserID: { nil },
            currentUsername: { nil }
        )

        await viewModel.loadProfile(username: "@Ada")

        XCTAssertEqual(viewModel.loadedUsername, "ada")
    }

    // The ownership check is on id, not handle

    func test_givenARenamedAccount_whenComparingOwnership_thenTheIdDecides() async {
        // A handle comparison would go wrong exactly where it matters — on a
        // rename, where the session's cached handle and the profile's disagree.
        let social = StubSocialService()
        await social.enqueueProfile(success: Self.profileFixture(id: "u-self", username: "ada-new"))
        await social.enqueueCounts(success: FollowCounts(followers: 0, following: 0))
        let viewModel = ProfileViewModel(
            social: social,
            relationshipReader: StubFollowRelationshipReader(),
            currentUserID: { "u-self" },
            currentUsername: { "ada-old" }
        )

        await viewModel.loadProfile(username: "ada-new")

        XCTAssertTrue(viewModel.isOwnProfile)
    }
}
