// ProfileHeaderViewModelTests
//
// BDD-named tests for the M5 additions to `ProfileViewModel`:
// mutual-counts follow-up, follow-button configuration, and soft-
// error handling for the mutual call. The M1 happy / error / empty
// paths for `loadProfile` and `counts` are covered by the existing
// behavior tests on the M1 view model and re-asserted here only
// where the M5 additions interact with them.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ProfileHeaderViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(
        currentUserID: String? = "user-ada"
    ) async -> (ProfileViewModel, StubSocialService, StubFollowRelationshipReader) {
        let social = StubSocialService()
        let reader = StubFollowRelationshipReader()
        let vm = ProfileViewModel(
            social: social,
            relationshipReader: reader,
            currentUserID: { currentUserID }
        )
        return (vm, social, reader)
    }

    private func sampleProfile(id: String = "user-bob", username: String = "bob") -> UserProfile {
        UserProfile(
            summary: UserSummary(id: id, username: username, displayName: "Bob", avatarURL: nil)
        )
    }

    // MARK: - load happy path

    func test_givenValidUsername_whenLoading_thenProfileCountsMutualsAndFollowButtonAreReady() async {
        let (vm, social, reader) = await makeViewModel()
        let profile = sampleProfile()
        await social.enqueueProfile(success: profile)
        await social.enqueueCounts(success: FollowCounts(followers: 5, following: 3))
        await social.enqueueMutual(success: MutualCounts(mutualFollowers: 2, mutualFollowing: 1))
        await reader.enqueue(
            FollowRelationship(isFollowing: false, isFollowedBy: false, hasPendingRequest: false),
            for: profile.id
        )

        await vm.loadProfile(username: "bob")

        XCTAssertEqual(vm.profile?.id, profile.id)
        XCTAssertEqual(vm.counts, FollowCounts(followers: 5, following: 3))
        XCTAssertEqual(vm.mutuals, MutualCounts(mutualFollowers: 2, mutualFollowing: 1))
        XCTAssertNotNil(vm.followButton)
        XCTAssertEqual(vm.followButton?.relationship?.state, .notFollowing)
    }

    // MARK: - invalid input

    func test_givenWhitespaceUsername_whenLoading_thenServiceIsNotCalled() async {
        let (vm, social, _) = await makeViewModel()

        await vm.loadProfile(username: "   ")

        let recorded = await social.recorded
        XCTAssertTrue(recorded.isEmpty, "Empty / whitespace input must short-circuit before the service")
    }

    // MARK: - upstream failure

    func test_givenProfileUnavailableError_whenLoading_thenSurfacesErrorAndLeavesEverythingNil() async {
        let (vm, social, _) = await makeViewModel()
        await social.enqueueProfile(failure: SocialError.profileUnavailable(username: "ghost"))

        await vm.loadProfile(username: "ghost")

        XCTAssertNil(vm.profile)
        XCTAssertNil(vm.counts)
        XCTAssertNil(vm.mutuals)
        XCTAssertNil(vm.followButton)
        guard let error = vm.error else {
            XCTFail("Expected profileUnavailable, got nil")
            return
        }
        if case let SocialError.profileUnavailable(username) = error {
            XCTAssertEqual(username, "ghost")
        } else {
            XCTFail("Expected profileUnavailable, got \(error)")
        }
    }

    // MARK: - empty / boundary — soft-error follow-ups

    func test_givenMutualCallFails_whenLoading_thenProfileStillRendersAndMutualsStayNil() async {
        // Soft-error policy: a failed mutual fetch is logged and the
        // profile remains the load-bearing data.
        let (vm, social, _) = await makeViewModel()
        let profile = sampleProfile()
        await social.enqueueProfile(success: profile)
        await social.enqueueCounts(success: FollowCounts(followers: 1, following: 1))
        await social.enqueueMutual(failure: TestError.upstream("mutual"))

        await vm.loadProfile(username: "bob")

        XCTAssertNotNil(vm.profile)
        XCTAssertNotNil(vm.counts)
        XCTAssertNil(vm.mutuals)
        XCTAssertNil(vm.error)
    }

    func test_givenSelfProfile_whenLoading_thenFollowButtonHidesItself() async {
        let (vm, social, _) = await makeViewModel(currentUserID: "user-ada")
        let me = sampleProfile(id: "user-ada", username: "ada")
        await social.enqueueProfile(success: me)
        await social.enqueueCounts(success: FollowCounts(followers: 0, following: 0))
        await social.enqueueMutual(success: MutualCounts.zero)

        await vm.loadProfile(username: "ada")

        XCTAssertNotNil(vm.followButton)
        XCTAssertTrue(vm.followButton?.isSelf == true)
        XCTAssertNil(vm.followButton?.relationship)
    }
}
