// NewMessageViewModelTests
//
// BDD-named tests for the new-message composer view model (work-consolidation.md
// G1). Covers the required quartet:
//   - happy: a picked recipient + non-blank body sends and reports the
//     sent message.
//   - invalid input: send with no recipient / blank body never calls the
//     service.
//   - upstream failure: a failing send surfaces the error.
//   - empty / boundary: an empty recipient list is reported so the sheet
//     can show its mutual-follow explanation.
//
// G22 adds the photo-attachment quartet, mirroring `DMThreadViewModelTests`:
//   - happy: attached photos upload and ride along on the send.
//   - invalid input: a 9th photo is refused client-side, with no upload.
//   - upstream failure: a failed upload does not lose the draft; the
//     message still sends as text and the failure surfaces (photo sending
//     needs a verified email — the server's 403 is what the user sees;
//     the gate itself is issue #41's).
//   - boundary: a 10,000-character body is accepted, 10,001 refused.

import XCTest
import InterlinedDomain
// The forbidden-refusal case asserts on the real `APIError`, so the
// server's wording is verified through the exact type production throws.
import InterlinedKit
@testable import InterlinedList

@MainActor
final class NewMessageViewModelTests: XCTestCase {

    private func makeViewModel(
        readData: @escaping @Sendable (URL) async throws -> Data = { _ in Data([0x1]) }
    ) -> (NewMessageViewModel, StubDirectMessagesService) {
        let service = StubDirectMessagesService()
        let vm = NewMessageViewModel(service: service, readData: readData)
        return (vm, service)
    }

    /// `n` distinct local image URLs. Nothing is read from disk — `readData`
    /// is stubbed — so these need not exist.
    private func photoURLs(_ n: Int) -> [URL] {
        (0..<n).map { URL(fileURLWithPath: "/tmp/dm-new-photo-\($0).png") }
    }

    private func uploadCallCount(_ recorded: [RecordedDMCall]) -> Int {
        recorded.filter { if case .uploadImage = $0.kind { return true } else { return false } }.count
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

    // MARK: - G22: photo attachments

    // Happy

    func test_givenAttachedPhotos_whenSending_thenUploadsEachAndSendsTheirURLs() async {
        let (vm, service) = makeViewModel()
        vm.seedRecipientsForTest([user("u1", "ada")])
        vm.selectedRecipientId = "u1"
        vm.body = "look"
        vm.addAttachments(urls: photoURLs(2))
        await service.enqueueUploadImage(success: "https://cdn/1.jpg")
        await service.enqueueUploadImage(success: "https://cdn/2.jpg")
        await service.enqueueSend(success: sent("m1", to: "u1"))

        await vm.send()

        let recorded = await service.recorded
        XCTAssertEqual(uploadCallCount(recorded), 2, "One upload per photo")
        XCTAssertTrue(recorded.contains(.init(kind: .send(
            recipientId: "u1", body: "look", imageURLs: ["https://cdn/1.jpg", "https://cdn/2.jpg"]
        ))), "The hosted URLs ride along on the send, in pick order")
        XCTAssertNotNil(vm.sentMessage)
        XCTAssertTrue(vm.attachments.isEmpty, "A sent draft's picks are cleared")
        XCTAssertNil(vm.error)
    }

    func test_givenOnlyPhotosAndNoBody_whenSending_thenTheMessageStillSends() async {
        let (vm, service) = makeViewModel()
        vm.seedRecipientsForTest([user("u1", "ada")])
        vm.selectedRecipientId = "u1"
        vm.addAttachments(urls: photoURLs(1))
        await service.enqueueUploadImage(success: "https://cdn/1.jpg")
        await service.enqueueSend(success: sent("m1", to: "u1"))

        XCTAssertTrue(vm.canSend, "A queued photo is enough to enable send")
        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .send(
            recipientId: "u1", body: "", imageURLs: ["https://cdn/1.jpg"]
        ))))
    }

    // Invalid input

    func test_givenNinthPhoto_whenAttaching_thenRefusedClientSideWithNoUploadCall() async {
        let (vm, service) = makeViewModel()

        vm.addAttachments(urls: photoURLs(9))

        XCTAssertEqual(vm.attachments.count, 8, "Only the documented 8 are kept")
        XCTAssertEqual(vm.error as? DMAttachmentError, .tooMany(limit: 8))
        let recorded = await service.recorded
        XCTAssertEqual(uploadCallCount(recorded), 0, "Nothing is uploaded at pick time")
    }

    func test_givenPhotosButNoRecipient_whenSending_thenRefusedBeforeAnyUpload() async {
        let (vm, service) = makeViewModel()
        vm.addAttachments(urls: photoURLs(1))

        await vm.send()

        XCTAssertEqual(vm.error as? NewMessageError, .noRecipient)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "No recipient → nothing is uploaded and nothing is sent")
    }

    // Upstream failure

    func test_givenUploadFails_whenSendingWithBody_thenMessageStillSendsAndFailureSurfaces() async {
        let (vm, service) = makeViewModel()
        vm.seedRecipientsForTest([user("u1", "ada")])
        vm.selectedRecipientId = "u1"
        vm.body = "text survives"
        vm.addAttachments(urls: photoURLs(1))
        await service.enqueueUploadImage(failure: TestError.upstream("upload-down"))
        await service.enqueueSend(success: sent("m1", to: "u1"))

        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(
            recorded.contains(.init(kind: .send(recipientId: "u1", body: "text survives", imageURLs: []))),
            "A failed photo must not cost the user their message"
        )
        XCTAssertNotNil(vm.sentMessage)
        XCTAssertEqual(vm.error as? TestError, .upstream("upload-down"), "The photo failure is still reported")
    }

    func test_givenEveryUploadFailsOnPhotoOnlyMessage_whenSending_thenNothingIsSentAndPicksSurvive() async {
        let (vm, service) = makeViewModel()
        vm.seedRecipientsForTest([user("u1", "ada")])
        vm.selectedRecipientId = "u1"
        vm.addAttachments(urls: photoURLs(1))
        await service.enqueueUploadImage(failure: TestError.upstream("upload-down"))

        await vm.send()

        let recorded = await service.recorded
        XCTAssertFalse(
            recorded.contains(where: { if case .send = $0.kind { return true } else { return false } }),
            "With nothing left to send, no send is attempted"
        )
        XCTAssertNil(vm.sentMessage)
        XCTAssertEqual(vm.attachments.count, 1, "The pick survives for a retry")
    }

    func test_givenServerRefusesUploadAsForbidden_whenSending_thenTheServerWordingIsSurfaced() async {
        // Photo sending requires a verified email address. We do not
        // pre-check that — issue #41 owns the gate — so the server's own
        // explanation is what the user must see, verbatim.
        let (vm, service) = makeViewModel()
        vm.seedRecipientsForTest([user("u1", "ada")])
        vm.selectedRecipientId = "u1"
        vm.body = "hi"
        vm.addAttachments(urls: photoURLs(1))
        await service.enqueueUploadImage(
            failure: APIError.forbidden(serverMessage: "Please verify your email address to send images.")
        )
        await service.enqueueSend(success: sent("m1", to: "u1"))

        await vm.send()

        XCTAssertEqual(
            vm.error?.localizedDescription,
            "Please verify your email address to send images.",
            "The refusal reaches the UI unrewritten"
        )
    }

    // Empty / boundary

    func test_givenExactlyEightPhotos_whenAttaching_thenAllAreAcceptedWithNoError() {
        let (vm, _) = makeViewModel()

        vm.addAttachments(urls: photoURLs(8))

        XCTAssertEqual(vm.attachments.count, 8)
        XCTAssertTrue(vm.attachmentsAreFull)
        XCTAssertNil(vm.error, "Exactly at the cap is not an error")
    }

    func test_givenTenThousandCharacterBody_whenSending_thenItIsAccepted() async {
        // The DM ceiling is 10,000 — not the post composer's 5,000.
        let (vm, service) = makeViewModel()
        vm.seedRecipientsForTest([user("u1", "ada")])
        vm.selectedRecipientId = "u1"
        let body = String(repeating: "a", count: 10_000)
        vm.body = body
        await service.enqueueSend(success: sent("m1", to: "u1"))

        XCTAssertFalse(vm.isOverBodyLimit)
        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .send(recipientId: "u1", body: body, imageURLs: []))))
    }

    func test_givenBodyOverTheLimit_whenSending_thenRefusedBeforeTheServiceIsCalled() async {
        let (vm, service) = makeViewModel()
        vm.seedRecipientsForTest([user("u1", "ada")])
        vm.selectedRecipientId = "u1"
        vm.body = String(repeating: "a", count: 10_001)

        XCTAssertTrue(vm.isOverBodyLimit)
        XCTAssertFalse(vm.canSend)
        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertEqual(vm.error as? NewMessageError, .bodyTooLong(limit: 10_000))
    }
}
