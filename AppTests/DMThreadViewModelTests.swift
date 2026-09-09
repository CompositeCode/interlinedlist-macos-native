// DMThreadViewModelTests
//
// BDD-named tests for the DM thread view model (work-consolidation.md G1). Covers
// the required quartet plus the optimistic-send rollback, mark-read-on-
// open, and the poll lifecycle (cancellation):
//   - happy: send appends optimistically then replaces with the server
//     message.
//   - invalid input: a blank draft never calls the service.
//   - upstream failure: a failing send removes the placeholder, restores
//     the draft, and surfaces the error.
//   - empty / boundary: loading an empty thread reports an empty list.
//   - optimistic rollback: asserted in the upstream-failure case.
//   - mark-read: opening a thread marks inbound-unread messages read and
//     posts the events.
//   - poll cancellation: stopPolling() ends the loop; no further
//     threadUpdates land after teardown.
//
// G22 adds the photo-attachment quartet:
//   - happy: attached photos upload and ride along on the send.
//   - invalid input: a 9th photo and a non-image are refused client-side,
//     with no upload call made.
//   - upstream failure: an upload that fails does not lose the draft — the
//     message still sends as text and the failure is surfaced. Sending
//     photos needs a verified email; the server's 403 is what surfaces
//     (the gate itself is issue #41's, not ours).
//   - boundary: exactly 8 photos are accepted; a 10,000-character body is
//     accepted and 10,001 is refused.

import XCTest
import InterlinedDomain
// The forbidden-refusal case asserts on the real `APIError`, so the
// server's wording is verified through the exact type production throws.
import InterlinedKit
@testable import InterlinedList

@MainActor
final class DMThreadViewModelTests: XCTestCase {

    // MARK: - Helpers

    private let me = "user-me"
    private let otherId = "user-ada"

    private func makeViewModel(
        pollInterval: Duration = .milliseconds(5),
        readData: @escaping @Sendable (URL) async throws -> Data = { _ in Data([0x1]) }
    ) -> (DMThreadViewModel, StubDirectMessagesService, DirectMessagesEventBus) {
        let service = StubDirectMessagesService()
        let bus = DirectMessagesEventBus()
        let vm = DMThreadViewModel(
            username: "ada",
            service: service,
            eventBus: bus,
            currentUserID: { [me] in me },
            pollInterval: pollInterval,
            readData: readData
        )
        return (vm, service, bus)
    }

    /// `n` distinct local image URLs. Nothing is read from disk — `readData`
    /// is stubbed — so these need not exist.
    private func photoURLs(_ n: Int) -> [URL] {
        (0..<n).map { URL(fileURLWithPath: "/tmp/dm-photo-\($0).png") }
    }

    private func uploadCallCount(_ recorded: [RecordedDMCall]) -> Int {
        recorded.filter { if case .uploadImage = $0.kind { return true } else { return false } }.count
    }

    private var ada: UserSummary {
        UserSummary(id: otherId, username: "ada", displayName: "Ada", avatarURL: nil)
    }

    private func inbound(_ id: String, read: Bool = false, at: TimeInterval) -> DirectMessage {
        DirectMessage(
            id: id, senderId: otherId, recipientId: me, body: "in \(id)",
            createdAt: Date(timeIntervalSince1970: at),
            readAt: read ? Date(timeIntervalSince1970: at) : nil,
            sender: ada, recipient: nil
        )
    }

    private func outbound(_ id: String, at: TimeInterval) -> DirectMessage {
        DirectMessage(
            id: id, senderId: me, recipientId: otherId, body: "out \(id)",
            createdAt: Date(timeIntervalSince1970: at),
            readAt: nil, sender: nil, recipient: ada
        )
    }

    private func serverMessage(_ id: String, body: String) -> DirectMessage {
        DirectMessage(
            id: id, senderId: me, recipientId: otherId, body: body,
            createdAt: Date(timeIntervalSince1970: 9_000), readAt: nil,
            sender: nil, recipient: ada
        )
    }

    // MARK: - Happy path (optimistic send → server replace)

    func test_givenMutualThread_whenSending_thenReplacesOptimisticWithServerMessage() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true)
        await service.enqueueSend(success: serverMessage("server-1", body: "hi"))

        vm.draft = "hi"
        await vm.send()

        XCTAssertEqual(vm.messages.map(\.id), ["m1", "server-1"], "Placeholder replaced by server id")
        XCTAssertEqual(vm.messages.last?.body, "hi")
        XCTAssertEqual(vm.draft, "", "Draft cleared on success")
        XCTAssertNil(vm.error)
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .send(recipientId: otherId, body: "hi", imageURLs: []))))
    }

    // MARK: - Invalid input (blank draft → no service call)

    func test_givenBlankDraft_whenSending_thenServiceIsNotCalled() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true)

        vm.draft = "   \n "
        await vm.send()

        let recorded = await service.recorded
        XCTAssertFalse(recorded.contains(where: { if case .send = $0.kind { return true } else { return false } }),
                       "A blank draft must not call send")
        XCTAssertEqual(vm.messages.count, 1, "No optimistic placeholder appended")
    }

    // MARK: - Upstream API failure (optimistic rollback)

    func test_givenSendFails_whenSending_thenRemovesPlaceholderAndRestoresDraft() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true)
        await service.enqueueSend(failure: TestError.upstream("offline"))

        vm.draft = "hello"
        await vm.send()

        XCTAssertEqual(vm.messages.map(\.id), ["m1"], "Optimistic placeholder removed on failure")
        XCTAssertEqual(vm.draft, "hello", "Draft restored so the user doesn't lose their text")
        XCTAssertEqual(vm.error as? TestError, .upstream("offline"))
    }

    // MARK: - Empty / boundary

    func test_givenEmptyThread_whenLoading_thenReportsEmptyAndHasLoadedOnce() async {
        let (vm, service, _) = makeViewModel()
        await service.enqueueThread(success: DMThread(messages: [], otherUser: ada, isMutual: true))

        await vm.load()

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertEqual(vm.otherUser?.username, "ada")
        XCTAssertTrue(vm.isMutual)
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    // MARK: - Non-mutual gate

    func test_givenNonMutualThread_whenLoaded_thenCannotSend() async {
        let (vm, service, _) = makeViewModel()
        await service.enqueueThread(success: DMThread(messages: [], otherUser: ada, isMutual: false))

        await vm.load()
        vm.draft = "hi"

        XCTAssertFalse(vm.canSend, "A non-mutual recipient can't be messaged")
    }

    // MARK: - Mark read on open

    func test_givenUnreadInbound_whenMarkingRead_thenCallsServiceAndPostsEvents() async {
        let (vm, service, bus) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", at: 100), inbound("m2", read: true, at: 200)], otherUser: ada, isMutual: true)
        await service.enqueueMarkReadSuccess()
        await service.enqueueUnreadCount(success: 0)

        // Capture the threadRead event.
        let readEvent = expectation(description: "threadRead")
        let task = Task {
            for await event in bus.events() {
                if case .threadRead(let username) = event, username == "ada" {
                    readEvent.fulfill(); return
                }
            }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.markInboundRead()

        await fulfillment(of: [readEvent], timeout: 1.0)
        task.cancel()
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .markRead(id: "m1"))), "Only the unread inbound message is marked")
        XCTAssertFalse(recorded.contains(.init(kind: .markRead(id: "m2"))), "The already-read message is skipped")
    }

    func test_givenNoUnreadInbound_whenMarkingRead_thenServiceIsNotCalled() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [outbound("m1", at: 100)], otherUser: ada, isMutual: true)

        await vm.markInboundRead()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "An all-outbound thread marks nothing")
    }

    // MARK: - Cancellation is not an error

    func test_givenLoadCancelled_whenLoading_thenLeavesErrorNilAndNotLoaded() async {
        // A cancelled thread load (view teardown / navigation) surfaces as
        // CancellationError from the client. It must not pin an error banner
        // nor flip `hasLoadedOnce`, which would flash a premature "Not mutual".
        let (vm, service, _) = makeViewModel()
        await service.enqueueThread(failure: CancellationError())

        await vm.load()

        XCTAssertNil(vm.error, "A cancelled load must not surface an error")
        XCTAssertFalse(vm.hasLoadedOnce, "A cancelled load did not complete")
    }

    func test_givenSendCancelled_whenSending_thenRestoresDraftWithoutError() async {
        // A cancelled send drops the optimistic bubble and restores the draft
        // (so the user can retry) but shows no error banner.
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true)
        await service.enqueueSend(failure: CancellationError())

        vm.draft = "hello"
        await vm.send()

        XCTAssertEqual(vm.messages.map(\.id), ["m1"], "Optimistic placeholder removed on cancel")
        XCTAssertEqual(vm.draft, "hello", "Draft restored for retry")
        XCTAssertNil(vm.error, "A cancelled send must not surface an error")
    }

    func test_givenStaleError_whenPollSucceeds_thenErrorIsCleared() async {
        // A genuine earlier failure pins the banner; once a poll round-trips
        // successfully the thread is proven live and the banner self-heals.
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true)
        await service.enqueueSend(failure: TestError.upstream("offline"))
        vm.draft = "hi"
        await vm.send()
        XCTAssertEqual(vm.error as? TestError, .upstream("offline"), "Precondition: banner is showing")

        await service.enqueueThreadUpdates(success: DMThread(messages: [], otherUser: ada, isMutual: true))
        await vm.pollOnce()

        XCTAssertNil(vm.error, "A successful poll clears the stale error banner")
    }

    // MARK: - Poll cycle + cancellation

    func test_givenPollCycle_whenNewMessageArrives_thenMergesIntoThread() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true)
        // pollOnce fetches threadUpdates then marks the new inbound read.
        await service.enqueueThreadUpdates(success: DMThread(messages: [inbound("m2", at: 200)], otherUser: ada, isMutual: true))
        await service.enqueueMarkReadSuccess()
        await service.enqueueUnreadCount(success: 0)

        await vm.pollOnce()

        XCTAssertEqual(vm.messages.map(\.id), ["m1", "m2"], "The polled message merged in place")
    }

    func test_givenRunningPoll_whenStopped_thenNoFurtherUpdatesLand() async {
        let (vm, service, _) = makeViewModel(pollInterval: .milliseconds(5))
        // Initial load for startPolling.
        await service.enqueueThread(success: DMThread(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true))
        // startPolling calls markInboundRead — nothing unread here, so no
        // markRead is consumed. Provide a generous number of threadUpdates
        // outcomes so an un-cancelled loop would consume them; after
        // stopPolling the count must stop growing.
        for _ in 0..<20 {
            await service.enqueueThreadUpdates(success: DMThread(messages: [], otherUser: ada, isMutual: true))
        }

        await vm.startPolling()
        // Let a few poll cycles run.
        try? await Task.sleep(nanoseconds: 40_000_000)
        vm.stopPolling()
        let countAfterStop = await service.recorded.filter { if case .threadUpdates = $0.kind { return true } else { return false } }.count
        // Wait well past several more intervals; the count must not grow.
        try? await Task.sleep(nanoseconds: 60_000_000)
        let countLater = await service.recorded.filter { if case .threadUpdates = $0.kind { return true } else { return false } }.count

        XCTAssertEqual(countAfterStop, countLater, "No threadUpdates fire after stopPolling")
    }

    // MARK: - G22: photo attachments

    // Happy

    func test_givenAttachedPhotos_whenSending_thenUploadsEachAndSendsTheirURLs() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true)
        vm.seedAttachmentsForTest(urls: photoURLs(2))
        await service.enqueueUploadImage(success: "https://cdn/1.jpg")
        await service.enqueueUploadImage(success: "https://cdn/2.jpg")
        await service.enqueueSend(success: DirectMessage(
            id: "server-1", senderId: me, recipientId: otherId, body: "look",
            imageURLs: [URL(string: "https://cdn/1.jpg")!, URL(string: "https://cdn/2.jpg")!],
            createdAt: Date(timeIntervalSince1970: 9_000), readAt: nil, sender: nil, recipient: ada
        ))
        vm.draft = "look"

        await vm.send()

        let recorded = await service.recorded
        XCTAssertEqual(uploadCallCount(recorded), 2, "One upload per photo")
        XCTAssertTrue(recorded.contains(.init(kind: .send(
            recipientId: otherId,
            body: "look",
            imageURLs: ["https://cdn/1.jpg", "https://cdn/2.jpg"]
        ))), "The hosted URLs ride along on the send, in pick order")
        XCTAssertEqual(vm.messages.last?.id, "server-1")
        XCTAssertEqual(vm.messages.last?.imageURLs.count, 2, "The photos appear in the thread")
        XCTAssertTrue(vm.attachments.isEmpty, "A sent draft's picks are cleared")
        XCTAssertNil(vm.error)
    }

    func test_givenOnlyPhotosAndNoText_whenSending_thenTheMessageStillSends() async {
        // A photo alone is a valid direct message.
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", read: true, at: 100)], otherUser: ada, isMutual: true)
        vm.seedAttachmentsForTest(urls: photoURLs(1))
        await service.enqueueUploadImage(success: "https://cdn/1.jpg")
        await service.enqueueSend(success: serverMessage("server-2", body: ""))

        XCTAssertTrue(vm.canSend, "A queued photo is enough to enable send")
        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .send(
            recipientId: otherId, body: "", imageURLs: ["https://cdn/1.jpg"]
        ))))
    }

    // Invalid input — refused before any upload

    func test_givenNinthPhoto_whenAttaching_thenRefusedClientSideWithNoUploadCall() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)

        vm.addAttachments(urls: photoURLs(9))

        XCTAssertEqual(vm.attachments.count, 8, "Only the documented 8 are kept")
        XCTAssertTrue(vm.attachmentsAreFull)
        XCTAssertEqual(vm.error as? DMAttachmentError, .tooMany(limit: 8))
        let recorded = await service.recorded
        XCTAssertEqual(uploadCallCount(recorded), 0, "Nothing is uploaded at pick time")
    }

    func test_givenNonImageFile_whenAttaching_thenRefusedWithNoUploadCall() async {
        // DMs have no video route, so a movie is refused with an explanation
        // rather than silently dropped.
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)

        vm.addAttachments(urls: [URL(fileURLWithPath: "/tmp/clip.mov")])

        XCTAssertTrue(vm.attachments.isEmpty)
        XCTAssertEqual(vm.error as? DMAttachmentError, .notAnImage)
        let recorded = await service.recorded
        XCTAssertEqual(uploadCallCount(recorded), 0)
    }

    // Upstream failure — the draft survives

    func test_givenUploadFails_whenSendingWithText_thenMessageStillSendsAndFailureSurfaces() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)
        vm.seedAttachmentsForTest(urls: photoURLs(1))
        await service.enqueueUploadImage(failure: TestError.upstream("upload-down"))
        await service.enqueueSend(success: serverMessage("server-3", body: "text survives"))
        vm.draft = "text survives"

        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(
            recorded.contains(.init(kind: .send(recipientId: otherId, body: "text survives", imageURLs: []))),
            "A failed photo must not cost the user their message"
        )
        XCTAssertEqual(vm.messages.last?.body, "text survives")
        XCTAssertEqual(vm.error as? TestError, .upstream("upload-down"), "The photo failure is still reported")
        XCTAssertEqual(vm.draft, "", "The message went out, so the draft is consumed")
    }

    func test_givenEveryUploadFailsOnPhotoOnlyMessage_whenSending_thenNothingIsSentAndPicksSurvive() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)
        vm.seedAttachmentsForTest(urls: photoURLs(1))
        await service.enqueueUploadImage(failure: TestError.upstream("upload-down"))

        await vm.send()

        let recorded = await service.recorded
        XCTAssertFalse(
            recorded.contains(where: { if case .send = $0.kind { return true } else { return false } }),
            "With nothing left to send, no send is attempted"
        )
        XCTAssertEqual(vm.error as? TestError, .upstream("upload-down"))
        XCTAssertEqual(vm.attachments.count, 1, "The pick survives for a retry")
    }

    func test_givenServerRefusesUploadAsForbidden_whenSending_thenTheServerWordingIsSurfaced() async {
        // Sending photos requires a verified email address. We do not
        // pre-check that — issue #41 owns the gate — so the server's own
        // explanation is what the user must see, verbatim.
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)
        vm.seedAttachmentsForTest(urls: photoURLs(1))
        await service.enqueueUploadImage(
            failure: APIError.forbidden(serverMessage: "Please verify your email address to send images.")
        )
        await service.enqueueSend(success: serverMessage("server-4", body: "hi"))
        vm.draft = "hi"

        await vm.send()

        XCTAssertEqual(
            vm.error?.localizedDescription,
            "Please verify your email address to send images.",
            "The refusal reaches the UI unrewritten"
        )
    }

    // Empty / boundary

    func test_givenExactlyEightPhotos_whenAttaching_thenAllAreAcceptedWithNoError() async {
        let (vm, _, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)

        vm.addAttachments(urls: photoURLs(8))

        XCTAssertEqual(vm.attachments.count, 8)
        XCTAssertTrue(vm.attachmentsAreFull)
        XCTAssertNil(vm.error, "Exactly at the cap is not an error")
    }

    func test_givenNoAttachmentsAndBlankDraft_whenSending_thenServiceIsNotCalled() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)
        vm.draft = "   "

        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "Nothing to send → nothing is called")
    }

    func test_givenTenThousandCharacterBody_whenSending_thenItIsAccepted() async {
        // The DM ceiling is 10,000 — not the post composer's 5,000.
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)
        let body = String(repeating: "a", count: 10_000)
        await service.enqueueSend(success: serverMessage("server-5", body: body))
        vm.draft = body

        XCTAssertFalse(vm.isOverBodyLimit)
        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .send(recipientId: otherId, body: body, imageURLs: []))))
    }

    func test_givenBodyOverTheLimit_whenSending_thenRefusedBeforeTheServiceIsCalled() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [], otherUser: ada, isMutual: true)
        vm.draft = String(repeating: "a", count: 10_001)

        XCTAssertTrue(vm.isOverBodyLimit)
        XCTAssertFalse(vm.canSend)
        await vm.send()

        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertEqual(vm.error as? DMThreadError, .bodyTooLong(limit: 10_000))
    }
}
