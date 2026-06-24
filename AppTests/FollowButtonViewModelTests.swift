// FollowButtonViewModelTests
//
// BDD-named tests for the M5 follow-button view model. Covers every
// state transition (notFollowing ↔ following, notFollowing → pending,
// pending → following), optimistic rollback on failure, and the
// self-profile / no-session hide cases.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class FollowButtonViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(
        defaultRelationship: FollowRelationship = FollowRelationship(
            isFollowing: false,
            isFollowedBy: false,
            hasPendingRequest: false
        )
    ) async -> (FollowButtonViewModel, StubSocialService, StubFollowRelationshipReader) {
        let social = StubSocialService()
        let reader = StubFollowRelationshipReader()
        await reader.setDefault(defaultRelationship)
        let viewModel = FollowButtonViewModel(social: social, reader: reader)
        return (viewModel, social, reader)
    }

    // MARK: - configure happy / boundary

    func test_givenAnotherUser_whenConfiguring_thenLoadsRelationshipAndStaysVisible() async {
        let (vm, _, reader) = await makeViewModel()
        await reader.enqueue(
            FollowRelationship(isFollowing: true, isFollowedBy: false, hasPendingRequest: false),
            for: "user-bob"
        )

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")

        XCTAssertEqual(vm.targetUserID, "user-bob")
        XCTAssertFalse(vm.isSelf)
        XCTAssertEqual(vm.relationship?.state, .following)
        XCTAssertNil(vm.error)
    }

    func test_givenSelfProfile_whenConfiguring_thenHidesButton() async {
        let (vm, _, reader) = await makeViewModel()

        await vm.configure(targetUserID: "user-ada", currentUserID: "user-ada")

        XCTAssertTrue(vm.isSelf)
        XCTAssertNil(vm.relationship)
        let probes = await reader.recordedUserIDs
        XCTAssertTrue(probes.isEmpty, "Self-profile must skip the relationship read")
    }

    func test_givenNoSession_whenConfiguring_thenLoadsRelationshipForVisibility() async {
        // A signed-out session still wants the read to render the
        // Follow button — the action will fail server-side, but the
        // button shouldn't blank out (it's the only way to sign-in
        // prompts surface on tap later).
        let (vm, _, reader) = await makeViewModel()

        await vm.configure(targetUserID: "user-bob", currentUserID: nil)

        XCTAssertFalse(vm.isSelf)
        let probes = await reader.recordedUserIDs
        XCTAssertEqual(probes, ["user-bob"])
    }

    func test_givenReaderFailure_whenConfiguring_thenSurfacesErrorAndKeepsRelationshipNil() async {
        let (vm, _, reader) = await makeViewModel()
        await reader.enqueueFailure(TestError.upstream("transport"), for: "user-bob")

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")

        XCTAssertNil(vm.relationship)
        XCTAssertEqual(vm.error as? TestError, .upstream("transport"))
    }

    // MARK: - tap follow

    func test_givenNotFollowing_whenTapping_thenOptimisticallyFollowsAndConfirms() async {
        let (vm, social, reader) = await makeViewModel()
        await reader.enqueue(
            FollowRelationship(isFollowing: false, isFollowedBy: false, hasPendingRequest: false),
            for: "user-bob"
        )
        await social.enqueueFollow(success: .approved)

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")
        await vm.tap()

        XCTAssertEqual(vm.relationship?.state, .following)
        XCTAssertNil(vm.error)
        let recorded = await social.recorded
        XCTAssertEqual(recorded.last?.kind, .follow(userId: "user-bob"))
    }

    func test_givenPrivateAccount_whenTapping_thenTransitionsToPendingRequest() async {
        let (vm, social, reader) = await makeViewModel()
        await reader.enqueue(
            FollowRelationship(isFollowing: false, isFollowedBy: false, hasPendingRequest: false),
            for: "user-bob"
        )
        await social.enqueueFollow(success: .pending)

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")
        await vm.tap()

        XCTAssertEqual(vm.relationship?.state, .pending)
    }

    func test_givenFollowFailure_whenTapping_thenRollsBackToNotFollowing() async {
        // Upstream API failure case for optimistic UI.
        let (vm, social, reader) = await makeViewModel()
        let initial = FollowRelationship(isFollowing: false, isFollowedBy: false, hasPendingRequest: false)
        await reader.enqueue(initial, for: "user-bob")
        await social.enqueueFollow(failure: TestError.upstream("forbidden"))

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")
        await vm.tap()

        XCTAssertEqual(vm.relationship?.state, .notFollowing)
        XCTAssertEqual(vm.error as? TestError, .upstream("forbidden"))
    }

    // MARK: - tap unfollow

    func test_givenFollowing_whenTapping_thenOptimisticallyUnfollows() async {
        let (vm, social, reader) = await makeViewModel()
        let initial = FollowRelationship(isFollowing: true, isFollowedBy: false, hasPendingRequest: false)
        await reader.enqueue(initial, for: "user-bob")
        await social.enqueueUnfollowSuccess()

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")
        await vm.tap()

        XCTAssertEqual(vm.relationship?.state, .notFollowing)
        let recorded = await social.recorded
        XCTAssertEqual(recorded.last?.kind, .unfollow(userId: "user-bob"))
    }

    func test_givenUnfollowFailure_whenTapping_thenRollsBackToFollowing() async {
        let (vm, social, reader) = await makeViewModel()
        let initial = FollowRelationship(isFollowing: true, isFollowedBy: false, hasPendingRequest: false)
        await reader.enqueue(initial, for: "user-bob")
        await social.enqueueUnfollow(failure: TestError.upstream("conflict"))

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")
        await vm.tap()

        XCTAssertEqual(vm.relationship?.state, .following)
        XCTAssertEqual(vm.error as? TestError, .upstream("conflict"))
    }

    // MARK: - pending → approved

    func test_givenPendingRequest_whenRefreshingAndServerApproved_thenStateBecomesFollowing() async {
        let (vm, _, reader) = await makeViewModel()
        await reader.enqueue(
            FollowRelationship(isFollowing: false, isFollowedBy: false, hasPendingRequest: true),
            for: "user-bob"
        )

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")
        XCTAssertEqual(vm.relationship?.state, .pending)

        // Refresh after server-side approval landed.
        await reader.enqueue(
            FollowRelationship(isFollowing: true, isFollowedBy: false, hasPendingRequest: false),
            for: "user-bob"
        )
        await vm.refresh()

        XCTAssertEqual(vm.relationship?.state, .following)
    }

    // MARK: - tap on pending is a no-op

    func test_givenPendingState_whenTapping_thenServiceIsNotCalled() async {
        let (vm, social, reader) = await makeViewModel()
        await reader.enqueue(
            FollowRelationship(isFollowing: false, isFollowedBy: false, hasPendingRequest: true),
            for: "user-bob"
        )

        await vm.configure(targetUserID: "user-bob", currentUserID: "user-ada")
        await vm.tap()

        let recorded = await social.recorded
        XCTAssertTrue(
            recorded.allSatisfy {
                if case .follow = $0.kind { return false }
                if case .unfollow = $0.kind { return false }
                return true
            },
            "Pending tap must not fire follow/unfollow"
        )
    }
}
