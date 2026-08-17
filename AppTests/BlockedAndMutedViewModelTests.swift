// BlockedAndMutedViewModelTests
//
// BDD-named tests for the Settings "Blocked & Muted" view model
// (work-consolidation.md G2). Covers the required quartet plus the optimistic-
// removal rollback:
//   - happy: load populates both rosters.
//   - invalid input (unblock unknown username): no service call, no row
//     change.
//   - upstream failure (load): surfaces error, sets hasLoadedOnce.
//   - empty / boundary: load with two empty rosters reports empty +
//     hasLoadedOnce.
//   - unblock happy: optimistic row removal + service call.
//   - unblock rollback: failure restores the removed row + surfaces error.
//   - unmute happy + rollback: same shape on the muted roster.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class BlockedAndMutedViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel() -> (BlockedAndMutedViewModel, StubModerationService) {
        let service = StubModerationService()
        let vm = BlockedAndMutedViewModel(service: service)
        return (vm, service)
    }

    private func user(_ username: String) -> ModeratedUser {
        ModeratedUser(id: "id-\(username)", username: username, displayName: username.capitalized, avatarURL: nil)
    }

    // MARK: - load

    func test_givenBlockedAndMuted_whenLoading_thenBothRostersPopulate() async {
        let (vm, service) = makeViewModel()
        await service.enqueueBlocked(success: [user("alice"), user("bob")])
        await service.enqueueMuted(success: [user("carol")])

        await vm.load()

        XCTAssertEqual(vm.blocked.map(\.username), ["alice", "bob"])
        XCTAssertEqual(vm.muted.map(\.username), ["carol"])
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    func test_givenEmptyRosters_whenLoading_thenReportsEmptyAndHasLoadedOnce() async {
        let (vm, service) = makeViewModel()
        await service.enqueueBlocked(success: [])
        await service.enqueueMuted(success: [])

        await vm.load()

        XCTAssertTrue(vm.blocked.isEmpty)
        XCTAssertTrue(vm.muted.isEmpty)
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    func test_givenLoadFailure_whenLoading_thenSurfacesErrorAndHasLoadedOnce() async {
        let (vm, service) = makeViewModel()
        await service.enqueueBlocked(failure: TestError.upstream("net"))
        await service.enqueueMuted(success: [])

        await vm.load()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    // MARK: - unblock

    func test_givenBlockedUser_whenUnblocking_thenRemovesRowAndCallsService() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(blocked: [user("alice"), user("bob")], muted: [])
        await service.enqueueUnblockSuccess()

        await vm.unblock(username: "alice")

        XCTAssertEqual(vm.blocked.map(\.username), ["bob"])
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains { if case .unblock(let u) = $0.kind { return u == "alice" } else { return false } })
    }

    func test_givenUnknownUsername_whenUnblocking_thenServiceIsNotCalled() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(blocked: [user("alice")], muted: [])

        await vm.unblock(username: "nobody")

        XCTAssertEqual(vm.blocked.map(\.username), ["alice"])
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "Unblocking an absent row must not call the service")
    }

    func test_givenUnblockFailure_whenUnblocking_thenRestoresRowAndSurfacesError() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(blocked: [user("alice"), user("bob")], muted: [])
        await service.enqueueUnblock(failure: TestError.upstream("net"))

        await vm.unblock(username: "alice")

        XCTAssertEqual(vm.blocked.map(\.username), ["alice", "bob"], "Failed unblock must restore the row")
        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
    }

    // MARK: - unmute

    func test_givenMutedUser_whenUnmuting_thenRemovesRowAndCallsService() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(blocked: [], muted: [user("carol"), user("dan")])
        await service.enqueueUnmuteSuccess()

        await vm.unmute(username: "carol")

        XCTAssertEqual(vm.muted.map(\.username), ["dan"])
        XCTAssertNil(vm.error)
    }

    func test_givenUnmuteFailure_whenUnmuting_thenRestoresRowAndSurfacesError() async {
        let (vm, service) = makeViewModel()
        vm.seedForTest(blocked: [], muted: [user("carol"), user("dan")])
        await service.enqueueUnmute(failure: TestError.upstream("net"))

        await vm.unmute(username: "carol")

        XCTAssertEqual(vm.muted.map(\.username), ["carol", "dan"])
        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
    }
}
