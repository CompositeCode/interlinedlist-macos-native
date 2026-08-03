// DMThreadViewModelTests
//
// BDD-named tests for the DM thread view model (the-gaps.md G1). Covers
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

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DMThreadViewModelTests: XCTestCase {

    // MARK: - Helpers

    private let me = "user-me"
    private let otherId = "user-ada"

    private func makeViewModel(pollInterval: Duration = .milliseconds(5)) -> (DMThreadViewModel, StubDirectMessagesService, DirectMessagesEventBus) {
        let service = StubDirectMessagesService()
        let bus = DirectMessagesEventBus()
        let vm = DMThreadViewModel(
            username: "ada",
            service: service,
            eventBus: bus,
            currentUserID: { [me] in me },
            pollInterval: pollInterval
        )
        return (vm, service, bus)
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
}
