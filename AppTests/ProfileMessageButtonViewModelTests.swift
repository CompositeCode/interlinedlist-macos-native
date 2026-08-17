// ProfileMessageButtonViewModelTests
//
// BDD-named tests for the profile "Message" button gate (work-consolidation.md G1).
// Covers the ownership-gating rule and eligibility:
//   - happy: an eligible (mutual recipient) profile shows the button.
//   - invalid input (self): messaging yourself is hidden without a call.
//   - ownership gate: an unresolved session hides the button (nil signal)
//     without a service call.
//   - upstream failure: a failing eligibility check fails closed (hidden).
//   - empty / boundary: a non-recipient profile hides the button.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ProfileMessageButtonViewModelTests: XCTestCase {

    private func makeViewModel(
        username: String,
        currentUsername: String?
    ) -> (ProfileMessageButtonViewModel, StubDirectMessagesService) {
        let service = StubDirectMessagesService()
        let vm = ProfileMessageButtonViewModel(
            username: username,
            service: service,
            currentUsername: { currentUsername }
        )
        return (vm, service)
    }

    private func user(_ id: String, _ username: String) -> UserSummary {
        UserSummary(id: id, username: username, displayName: username.capitalized, avatarURL: nil)
    }

    // MARK: - Happy path (eligible recipient shows the button)

    func test_givenMutualRecipient_whenChecking_thenButtonShows() async {
        let (vm, service) = makeViewModel(username: "ada", currentUsername: "me")
        await service.enqueueRecipients(success: [user("u1", "ada"), user("u2", "bob")])

        await vm.check()

        XCTAssertEqual(vm.isEligible, true)
        XCTAssertTrue(vm.shouldShow)
    }

    // MARK: - Invalid input (self-profile)

    func test_givenSelfProfile_whenChecking_thenHiddenWithoutServiceCall() async {
        let (vm, service) = makeViewModel(username: "me", currentUsername: "me")

        await vm.check()

        XCTAssertEqual(vm.isEligible, false)
        XCTAssertFalse(vm.shouldShow)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "Self-profile never checks recipients")
    }

    // MARK: - Ownership gate (unresolved session)

    func test_givenUnresolvedSession_whenChecking_thenHiddenWithoutServiceCall() async {
        let (vm, service) = makeViewModel(username: "ada", currentUsername: nil)

        await vm.check()

        XCTAssertNil(vm.isEligible, "Nil current user is the hidden/undetermined signal")
        XCTAssertFalse(vm.shouldShow)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "An unresolved session never touches the network")
    }

    // MARK: - Upstream failure (fail closed)

    func test_givenRecipientsFail_whenChecking_thenFailsClosedHidden() async {
        let (vm, service) = makeViewModel(username: "ada", currentUsername: "me")
        await service.enqueueRecipients(failure: TestError.upstream("net"))

        await vm.check()

        XCTAssertEqual(vm.isEligible, false, "A broken check fails closed")
        XCTAssertFalse(vm.shouldShow)
    }

    // MARK: - Empty / boundary (non-recipient)

    func test_givenNonRecipient_whenChecking_thenHidden() async {
        let (vm, service) = makeViewModel(username: "carol", currentUsername: "me")
        await service.enqueueRecipients(success: [user("u1", "ada")])

        await vm.check()

        XCTAssertEqual(vm.isEligible, false)
        XCTAssertFalse(vm.shouldShow)
    }
}
