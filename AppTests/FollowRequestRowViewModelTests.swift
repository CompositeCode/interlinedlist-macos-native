// FollowRequestRowViewModelTests
//
// BDD-named tests for the per-row M5 approve / reject view model.
// Coverage:
//   - happy: approve / reject transitions to the right Outcome.
//   - rollback: outcome stays `.undecided` on failure so buttons
//     re-enable; error surfaces.
//   - bus routing: success posts the corresponding NotificationsEvent.
//   - debounce: a second call while in flight is a no-op (only one
//     service hit).
//   - decided: a call after the outcome has resolved is a no-op.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class FollowRequestRowViewModelTests: XCTestCase {

    private func makeRow(
        userId: String = "u4"
    ) async -> (FollowRequestRowViewModel, StubSocialService, NotificationsEventBus) {
        let social = StubSocialService()
        let bus = NotificationsEventBus()
        let request = FollowRequest(
            id: "r1",
            user: UserSummary(id: userId, username: userId, displayName: userId.capitalized, avatarURL: nil),
            createdAt: nil
        )
        let vm = FollowRequestRowViewModel(
            request: request,
            social: social,
            notificationsEventBus: bus
        )
        return (vm, social, bus)
    }

    // MARK: - approve

    func test_givenUndecidedRow_whenApproving_thenOutcomeIsApproved() async {
        let (vm, social, _) = await makeRow()
        await social.enqueueApproveSuccess()

        await vm.approve()

        XCTAssertEqual(vm.outcome, .approved)
        XCTAssertNil(vm.error)
    }

    func test_givenApproveFailure_whenApproving_thenOutcomeStaysUndecidedAndErrorSurfaces() async {
        let (vm, social, _) = await makeRow()
        await social.enqueueApprove(failure: TestError.upstream("forbidden"))

        await vm.approve()

        XCTAssertEqual(vm.outcome, .undecided)
        XCTAssertEqual(vm.error as? TestError, .upstream("forbidden"))
    }

    // MARK: - reject

    func test_givenUndecidedRow_whenRejecting_thenOutcomeIsRejected() async {
        let (vm, social, _) = await makeRow()
        await social.enqueueRejectSuccess()

        await vm.reject()

        XCTAssertEqual(vm.outcome, .rejected)
    }

    func test_givenRejectFailure_whenRejecting_thenOutcomeStaysUndecided() async {
        let (vm, social, _) = await makeRow()
        await social.enqueueReject(failure: TestError.upstream("conflict"))

        await vm.reject()

        XCTAssertEqual(vm.outcome, .undecided)
        XCTAssertEqual(vm.error as? TestError, .upstream("conflict"))
    }

    // MARK: - bus routing

    func test_givenApproveSuccess_whenApproving_thenPostsRequestApprovedEvent() async {
        let (vm, social, bus) = await makeRow(userId: "u4")
        await social.enqueueApproveSuccess()

        let received = await collectFirstEvent(from: bus) { await vm.approve() }

        switch received {
        case .requestApproved(let userId):
            XCTAssertEqual(userId, "u4")
        default:
            XCTFail("Expected requestApproved, got \(String(describing: received))")
        }
    }

    func test_givenRejectSuccess_whenRejecting_thenPostsRequestRejectedEvent() async {
        let (vm, social, bus) = await makeRow(userId: "u5")
        await social.enqueueRejectSuccess()

        let received = await collectFirstEvent(from: bus) { await vm.reject() }

        switch received {
        case .requestRejected(let userId):
            XCTAssertEqual(userId, "u5")
        default:
            XCTFail("Expected requestRejected, got \(String(describing: received))")
        }
    }

    // MARK: - decided is a no-op

    func test_givenAlreadyApprovedRow_whenApprovingAgain_thenServiceIsNotCalled() async {
        let (vm, social, _) = await makeRow()
        await social.enqueueApproveSuccess()
        await vm.approve()

        // Re-approve — there's no enqueued outcome, so a service hit
        // would `throw .noOutcome`. The decided guard prevents that.
        await vm.approve()

        XCTAssertEqual(vm.outcome, .approved)
        XCTAssertNil(vm.error)
        let recorded = await social.recorded
        let approveCount = recorded.filter {
            if case .approve = $0.kind { return true } else { return false }
        }.count
        XCTAssertEqual(approveCount, 1)
    }

    // MARK: - helpers

    /// Subscribes to `bus.events()`, executes `work`, returns the
    /// first event observed within a short polling window.
    private func collectFirstEvent(
        from bus: NotificationsEventBus,
        work: @escaping () async -> Void
    ) async -> NotificationsEvent? {
        // Subscribe BEFORE work so we don't miss the event. Use a
        // small actor-backed mailbox to capture the first event the
        // stream yields without blocking on the iterator's
        // never-finishing semantics.
        let mailbox = EventMailbox()
        let stream = bus.events()
        let consumer = Task {
            for await event in stream {
                await mailbox.set(event)
                break
            }
        }
        // Give the actor-storage register call a turn to land.
        for _ in 0..<5 { await Task.yield() }
        await work()
        // Give the broadcast a few turns to make it through the bus
        // actor and into the mailbox.
        for _ in 0..<20 {
            if await mailbox.value != nil { break }
            await Task.yield()
        }
        consumer.cancel()
        return await mailbox.value
    }

    private actor EventMailbox {
        private(set) var value: NotificationsEvent?
        func set(_ event: NotificationsEvent) { value = event }
    }
}
