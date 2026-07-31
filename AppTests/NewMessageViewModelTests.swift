// NewMessageViewModelTests
//
// BDD-named tests for the new-message composer view model (the-gaps.md
// G1). Covers the required quartet:
//   - happy: a picked recipient + non-blank body sends and reports the
//     sent message.
//   - invalid input: send with no recipient / blank body never calls the
//     service.
//   - upstream failure: a failing send surfaces the error.
//   - empty / boundary: an empty recipient list is reported so the sheet
//     can show its "no mutual followers" state.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class NewMessageViewModelTests: XCTestCase {

    private func makeViewModel() -> (NewMessageViewModel, StubDirectMessagesService) {
        let service = StubDirectMessagesService()
        let vm = NewMessageViewModel(service: service)
        return (vm, service)
    }

    private func user(_ id: String, _ username: String) -> UserSummary {
        UserSummary(id: id, username: username, displayName: username.capitalized, avatarURL: nil)
    }

    private func sent(_ id: String, to recipient: String) -> DirectMessage {
        DirectMessage(
            id: id, senderId: "user-me", recipientId: recipient, body: "hi",
            createdAt: Date(timeIntervalSince1970: 1_000), readAt: nil,
            sender: nil, recipient: nil
        )
    }

    // MARK: - Recipient load

    func test_givenRecipients_whenLoading_thenPopulatesList() async {
        let (vm, service) = makeViewModel()
        await service.enqueueRecipients(success: [user("u1", "ada"), user("u2", "bob")])

        await vm.loadRecipients()

        XCTAssertEqual(vm.recipients.map(\.username), ["ada", "bob"])
        XCTAssertTrue(vm.hasLoadedRecipients)
    }

    func test_givenPreselectUsername_whenLoading_thenAutoSelectsMatch() async {
        let (vm, service) = makeViewModel()
        await service.enqueueRecipients(success: [user("u1", "ada"), user("u2", "bob")])

        await vm.loadRecipients(preselectUsername: "bob")

        XCTAssertEqual(vm.selectedRecipientId, "u2")
    }

    // MARK: - Happy path

    func test_givenRecipientAndBody_whenSending_thenReportsSentMessage() async {
        let (vm, service) = makeViewModel()
        await service.enqueueRecipients(success: [user("u1", "ada")])
        await service.enqueueSend(success: sent("s1", to: "u1"))
        await vm.loadRecipients()
        vm.selectedRecipientId = "u1"
        vm.body = "hi"

        await vm.send()

        XCTAssertEqual(vm.sentMessage?.id, "s1")
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.selectedRecipientUsername, "ada")
    }

    // MARK: - Invalid input

    func test_givenNoRecipient_whenSending_thenRejectedWithoutServiceCall() async {
        let (vm, service) = makeViewModel()
        vm.body = "hi"

        await vm.send()

        XCTAssertEqual(vm.error as? NewMessageError, .noRecipient)
        let recorded = await service.recorded
        XCTAssertFalse(recorded.contains(where: { if case .send = $0.kind { return true } else { return false } }))
    }

    func test_givenBlankBody_whenSending_thenRejectedWithoutServiceCall() async {
        let (vm, service) = makeViewModel()
        vm.selectedRecipientId = "u1"
        vm.body = "   "

        await vm.send()

        XCTAssertEqual(vm.error as? NewMessageError, .emptyBody)
        let recorded = await service.recorded
        XCTAssertFalse(recorded.contains(where: { if case .send = $0.kind { return true } else { return false } }))
    }

    // MARK: - Upstream failure

    func test_givenSendFails_whenSending_thenSurfacesError() async {
        let (vm, service) = makeViewModel()
        await service.enqueueSend(failure: TestError.upstream("boom"))
        vm.selectedRecipientId = "u1"
        vm.body = "hi"

        await vm.send()

        XCTAssertEqual(vm.error as? TestError, .upstream("boom"))
        XCTAssertNil(vm.sentMessage)
    }

    // MARK: - Empty / boundary

    func test_givenNoMutualFollowers_whenLoading_thenReportsEmptyList() async {
        let (vm, service) = makeViewModel()
        await service.enqueueRecipients(success: [])

        await vm.loadRecipients()

        XCTAssertTrue(vm.recipients.isEmpty)
        XCTAssertTrue(vm.hasLoadedRecipients)
        XCTAssertFalse(vm.canSend)
    }

    func test_givenRecipientsFail_whenLoading_thenSurfacesError() async {
        let (vm, service) = makeViewModel()
        await service.enqueueRecipients(failure: TestError.upstream("net"))

        await vm.loadRecipients()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.hasLoadedRecipients)
    }
}
