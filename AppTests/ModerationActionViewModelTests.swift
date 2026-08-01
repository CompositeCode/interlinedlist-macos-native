// ModerationActionViewModelTests
//
// BDD-named tests for the reusable moderation-action view model
// (the-gaps.md G2) that backs `ModerationMenu` + `ReportReasonSheet`.
// Covers the required quartet across the block / report surfaces:
//   - happy: block flips isBlocked + calls the service.
//   - invalid input: reportMessage on a profile subject (no messageID)
//     is rejected before any service call.
//   - upstream failure: a failing block surfaces the error and leaves
//     isBlocked false.
//   - empty / boundary: reportUser with an empty detail still submits
//     (empty detail is a valid "no detail" case; the domain normalizes
//     it to nil).
//   - report happy: reportMessage on a message subject submits + sets
//     didSubmitReport, forwarding the chosen reason.
//   - mute happy + failure symmetry.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ModerationActionViewModelTests: XCTestCase {

    private func makeUserSubject() -> (ModerationActionViewModel, StubModerationService) {
        let service = StubModerationService()
        let vm = ModerationActionViewModel(username: "alice", messageID: nil, service: service)
        return (vm, service)
    }

    private func makeMessageSubject() -> (ModerationActionViewModel, StubModerationService) {
        let service = StubModerationService()
        let vm = ModerationActionViewModel(username: "alice", messageID: "m1", service: service)
        return (vm, service)
    }

    // MARK: - block

    func test_givenUserSubject_whenBlocking_thenFlipsBlockedAndCallsService() async {
        let (vm, service) = makeUserSubject()
        await service.enqueueBlockSuccess()

        await vm.block()

        XCTAssertTrue(vm.isBlocked)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains { if case .block(let u) = $0.kind { return u == "alice" } else { return false } })
    }

    func test_givenBlockFailure_whenBlocking_thenSurfacesErrorAndStaysUnblocked() async {
        let (vm, service) = makeUserSubject()
        await service.enqueueBlock(failure: TestError.upstream("net"))

        await vm.block()

        XCTAssertFalse(vm.isBlocked)
        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
    }

    // MARK: - mute

    func test_givenUserSubject_whenMuting_thenFlipsMutedAndCallsService() async {
        let (vm, service) = makeUserSubject()
        await service.enqueueMuteSuccess()

        await vm.mute()

        XCTAssertTrue(vm.isMuted)
        XCTAssertNil(vm.error)
    }

    // MARK: - reportMessage invalid input

    func test_givenProfileSubject_whenReportingMessage_thenRejectedBeforeServiceCall() async {
        let (vm, service) = makeUserSubject() // no messageID

        await vm.reportMessage(reason: .spam, detail: nil)

        XCTAssertEqual(vm.error as? ModerationActionError, .noMessageSubject)
        XCTAssertFalse(vm.didSubmitReport)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "A message report with no message subject must not hit the service")
    }

    func test_givenProfileSubject_whenReportingMessage_thenCanReportMessageIsFalse() async {
        let (vm, _) = makeUserSubject()
        XCTAssertFalse(vm.canReportMessage)
    }

    // MARK: - reportMessage happy

    func test_givenMessageSubject_whenReportingMessage_thenSubmitsWithReason() async {
        let (vm, service) = makeMessageSubject()
        await service.enqueueReportMessageSuccess()

        await vm.reportMessage(reason: .harassment, detail: "abusive")

        XCTAssertTrue(vm.didSubmitReport)
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains {
            if case .reportMessage(let id, let reason, let detail) = $0.kind {
                return id == "m1" && reason == .harassment && detail == "abusive"
            }
            return false
        })
    }

    // MARK: - reportUser boundary (empty detail)

    func test_givenUserSubject_whenReportingWithNilDetail_thenSubmitsSuccessfully() async {
        let (vm, service) = makeUserSubject()
        await service.enqueueReportUserSuccess()

        await vm.reportUser(reason: .other, detail: nil)

        XCTAssertTrue(vm.didSubmitReport)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains {
            if case .reportUser(let u, let reason, let detail) = $0.kind {
                return u == "alice" && reason == .other && detail == nil
            }
            return false
        })
    }

    func test_givenReportUserFailure_whenReporting_thenSurfacesErrorAndDidNotSubmit() async {
        let (vm, service) = makeUserSubject()
        await service.enqueueReportUser(failure: TestError.upstream("net"))

        await vm.reportUser(reason: .spam, detail: nil)

        XCTAssertFalse(vm.didSubmitReport)
        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
    }
}
