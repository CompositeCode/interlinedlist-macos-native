// SocialRosterViewModelTests
//
// BDD-named tests for the M5 Followers / Following / Requests panel
// view model. Each tab gets the standard happy / empty / failure
// quartet, plus pagination coverage for the followers / following
// tabs and approve / reject optimistic-rollback coverage for the
// requests tab.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class SocialRosterViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(
        targetUserID: String = "user-ada"
    ) async -> (SocialRosterViewModel, StubSocialService) {
        let social = StubSocialService()
        let vm = SocialRosterViewModel(
            social: social,
            targetUserID: targetUserID
        )
        return (vm, social)
    }

    private func user(id: String, username: String) -> UserSummary {
        UserSummary(id: id, username: username, displayName: username.capitalized, avatarURL: nil)
    }

    // MARK: - Followers

    func test_givenPopulatedFollowers_whenLoading_thenRendersListAndPagination() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueFollowers(success: UsersPage(
            users: [user(id: "u1", username: "u1"), user(id: "u2", username: "u2")],
            hasMore: true,
            nextOffset: 2
        ))

        await vm.loadFollowers(reset: true)

        XCTAssertEqual(vm.followers.map(\.id), ["u1", "u2"])
        XCTAssertTrue(vm.followersHasMore)
        XCTAssertEqual(vm.followersNextOffset, 2)
        XCTAssertNil(vm.followersError)
    }

    func test_givenEmptyFollowersPage_whenLoading_thenListIsEmptyAndNoMore() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueFollowers(success: UsersPage.empty)

        await vm.loadFollowers(reset: true)

        XCTAssertTrue(vm.followers.isEmpty)
        XCTAssertFalse(vm.followersHasMore)
        XCTAssertNil(vm.followersNextOffset)
    }

    func test_givenFollowersFailure_whenLoading_thenSurfacesError() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueFollowers(failure: TestError.upstream("net"))

        await vm.loadFollowers(reset: true)

        XCTAssertTrue(vm.followers.isEmpty)
        XCTAssertEqual(vm.followersError as? TestError, .upstream("net"))
    }

    func test_givenSecondPage_whenLoadingMore_thenAppendsRows() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueFollowers(success: UsersPage(
            users: [user(id: "u1", username: "u1")],
            hasMore: true,
            nextOffset: 1
        ))
        await social.enqueueFollowers(success: UsersPage(
            users: [user(id: "u2", username: "u2")],
            hasMore: false,
            nextOffset: nil
        ))

        await vm.loadFollowers(reset: true)
        await vm.loadFollowers(reset: false)

        XCTAssertEqual(vm.followers.map(\.id), ["u1", "u2"])
        XCTAssertFalse(vm.followersHasMore)
    }

    // MARK: - Following

    func test_givenPopulatedFollowing_whenLoading_thenRendersList() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueFollowing(success: UsersPage(
            users: [user(id: "u3", username: "u3")],
            hasMore: false,
            nextOffset: nil
        ))

        await vm.loadFollowing(reset: true)

        XCTAssertEqual(vm.following.map(\.id), ["u3"])
    }

    func test_givenFollowingFailure_whenLoading_thenSurfacesError() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueFollowing(failure: TestError.upstream("net"))

        await vm.loadFollowing(reset: true)

        XCTAssertTrue(vm.following.isEmpty)
        XCTAssertEqual(vm.followingError as? TestError, .upstream("net"))
    }

    // MARK: - Requests load

    func test_givenPopulatedRequests_whenLoading_thenRendersList() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueRequests(success: [
            FollowRequest(id: "r1", user: user(id: "u4", username: "u4"), createdAt: nil)
        ])

        await vm.loadRequests()

        XCTAssertEqual(vm.requests.map(\.id), ["r1"])
    }

    func test_givenEmptyRequests_whenLoading_thenListIsEmpty() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueRequests(success: [])

        await vm.loadRequests()

        XCTAssertTrue(vm.requests.isEmpty)
    }

    func test_givenRequestsFailure_whenLoading_thenSurfacesError() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueRequests(failure: TestError.upstream("net"))

        await vm.loadRequests()

        XCTAssertEqual(vm.requestsError as? TestError, .upstream("net"))
    }

    // MARK: - Approve / Reject optimistic + rollback

    func test_givenPendingRequest_whenApproving_thenRowDropsOptimisticallyAndStays() async {
        let (vm, social) = await makeViewModel()
        let req = FollowRequest(id: "r1", user: user(id: "u4", username: "u4"), createdAt: nil)
        await social.enqueueRequests(success: [req])
        await social.enqueueApproveSuccess()
        await vm.loadRequests()

        let error = await vm.approve(request: req)

        XCTAssertNil(error)
        XCTAssertTrue(vm.requests.isEmpty)
    }

    func test_givenApproveFails_whenApproving_thenRowIsRestoredAndErrorSurfaces() async {
        let (vm, social) = await makeViewModel()
        let req = FollowRequest(id: "r1", user: user(id: "u4", username: "u4"), createdAt: nil)
        await social.enqueueRequests(success: [req])
        await social.enqueueApprove(failure: TestError.upstream("forbidden"))
        await vm.loadRequests()

        let error = await vm.approve(request: req)

        XCTAssertEqual(error as? TestError, .upstream("forbidden"))
        XCTAssertEqual(vm.requests.map(\.id), ["r1"])
        XCTAssertEqual(vm.requestsError as? TestError, .upstream("forbidden"))
    }

    func test_givenPendingRequest_whenRejecting_thenRowDropsOptimistically() async {
        let (vm, social) = await makeViewModel()
        let req = FollowRequest(id: "r1", user: user(id: "u4", username: "u4"), createdAt: nil)
        await social.enqueueRequests(success: [req])
        await social.enqueueRejectSuccess()
        await vm.loadRequests()

        let error = await vm.reject(request: req)

        XCTAssertNil(error)
        XCTAssertTrue(vm.requests.isEmpty)
    }

    func test_givenRejectFails_whenRejecting_thenRowIsRestoredAndErrorSurfaces() async {
        let (vm, social) = await makeViewModel()
        let req = FollowRequest(id: "r1", user: user(id: "u4", username: "u4"), createdAt: nil)
        await social.enqueueRequests(success: [req])
        await social.enqueueReject(failure: TestError.upstream("conflict"))
        await vm.loadRequests()

        let error = await vm.reject(request: req)

        XCTAssertEqual(error as? TestError, .upstream("conflict"))
        XCTAssertEqual(vm.requests.map(\.id), ["r1"])
    }

    // MARK: - Initial load fan-out

    func test_givenInitialLoad_whenCalled_thenAllThreeTabsAreFetched() async {
        let (vm, social) = await makeViewModel()
        await social.enqueueFollowers(success: UsersPage(users: [], hasMore: false, nextOffset: nil))
        await social.enqueueFollowing(success: UsersPage(users: [], hasMore: false, nextOffset: nil))
        await social.enqueueRequests(success: [])

        await vm.initialLoad()

        let recorded = await social.recorded
        let kinds = recorded.map(\.kind)
        XCTAssertTrue(kinds.contains { if case .followers = $0 { return true } else { return false } })
        XCTAssertTrue(kinds.contains { if case .following = $0 { return true } else { return false } })
        XCTAssertTrue(kinds.contains { if case .requests = $0 { return true } else { return false } })
    }
}
