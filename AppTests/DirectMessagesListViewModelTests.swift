// DirectMessagesListViewModelTests
//
// BDD-named tests for the DM conversation-list view model (work-consolidation.md
// G1). Covers the required quartet plus pagination and the optimistic
// trash/restore rollback:
//   - happy: a folder load groups the flat listing into conversations.
//   - invalid input: trashing an id not in the list makes no service call.
//   - upstream failure: a failing folder load surfaces the error.
//   - empty / boundary: an empty page reports an empty list + hasLoadedOnce.
//   - pagination: nextCursor is surfaced (hasMore) and loadMore appends;
//     a zero-item page boundary clears hasMore.
//   - optimistic: trash drops the row locally; a failing trash restores it.
//
// Tests drive the view model through its intents and await, so assertions
// are deterministic.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DirectMessagesListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private let me = "user-me"

    private func makeViewModel() -> (DirectMessagesListViewModel, StubDirectMessagesService, DirectMessagesEventBus) {
        let service = StubDirectMessagesService()
        let bus = DirectMessagesEventBus()
        let vm = DirectMessagesListViewModel(
            service: service,
            eventBus: bus,
            currentUserID: { [me] in me }
        )
        return (vm, service, bus)
    }

    private func other(_ id: String, _ username: String) -> UserSummary {
        UserSummary(id: id, username: username, displayName: username.capitalized, avatarURL: nil)
    }

    /// An inbound message (they → me).
    private func inbound(_ id: String, from otherId: String, username: String, read: Bool = false, at: TimeInterval) -> DirectMessage {
        DirectMessage(
            id: id,
            senderId: otherId,
            recipientId: me,
            body: "in \(id)",
            createdAt: Date(timeIntervalSince1970: at),
            readAt: read ? Date(timeIntervalSince1970: at) : nil,
            sender: other(otherId, username),
            recipient: nil
        )
    }

    // MARK: - Happy path

    func test_givenFolderPage_whenLoading_thenGroupsMessagesIntoConversations() async {
        let (vm, service, _) = makeViewModel()
        await service.enqueueFolder(success: DMPage(messages: [
            inbound("m3", from: "user-ada", username: "ada", at: 300),
            inbound("m2", from: "user-ada", username: "ada", read: true, at: 200),
            inbound("m1", from: "user-bob", username: "bob", at: 100)
        ], nextCursor: nil))
        await service.enqueueUnreadCount(success: 1)

        await vm.load()

        XCTAssertEqual(vm.conversations.count, 2, "Two distinct participants → two rows")
        XCTAssertEqual(vm.conversations.first?.otherUsername, "ada")
        XCTAssertEqual(vm.conversations.first?.latestMessage.id, "m3", "Newest message is the preview")
        XCTAssertEqual(vm.conversations.first?.unreadCount, 1, "m3 unread, m2 read")
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    // MARK: - Invalid input (no-op trash of an absent id)

    func test_givenMessageIdNotInList_whenTrashing_thenServiceIsNotCalled() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [inbound("m1", from: "user-ada", username: "ada", at: 100)])

        await vm.trash(messageID: "does-not-exist")

        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "Trashing an absent id must not call the service")
        XCTAssertEqual(vm.conversations.count, 1, "The list is untouched")
    }

    // MARK: - Upstream API failure

    func test_givenUpstreamFailure_whenLoading_thenSurfacesErrorAndHasLoadedOnce() async {
        let (vm, service, _) = makeViewModel()
        await service.enqueueFolder(failure: TestError.upstream("net"))
        await service.enqueueUnreadCount(success: 0)

        await vm.load()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.conversations.isEmpty)
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    // MARK: - Empty / boundary

    func test_givenEmptyPage_whenLoading_thenReportsEmptyAndHasLoadedOnce() async {
        let (vm, service, _) = makeViewModel()
        await service.enqueueFolder(success: .empty)
        await service.enqueueUnreadCount(success: 0)

        await vm.load()

        XCTAssertTrue(vm.conversations.isEmpty)
        XCTAssertFalse(vm.hasMore)
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    // MARK: - Pagination

    func test_givenNextCursor_whenLoading_thenHasMoreIsSurfaced() async {
        let (vm, service, _) = makeViewModel()
        await service.enqueueFolder(success: DMPage(
            messages: [inbound("m1", from: "user-ada", username: "ada", at: 100)],
            nextCursor: "cursor-2"
        ))
        await service.enqueueUnreadCount(success: 0)

        await vm.load()

        XCTAssertTrue(vm.hasMore)
        XCTAssertEqual(vm.nextCursor, "cursor-2")
    }

    func test_givenNextCursor_whenLoadingMore_thenAppendsAndClearsCursorOnZeroItemPage() async {
        let (vm, service, _) = makeViewModel()
        await service.enqueueFolder(success: DMPage(
            messages: [inbound("m1", from: "user-ada", username: "ada", at: 100)],
            nextCursor: "cursor-2"
        ))
        await service.enqueueUnreadCount(success: 0)
        await vm.load()
        XCTAssertTrue(vm.hasMore)

        // Zero-item next page → hasMore clears.
        await service.enqueueFolder(success: DMPage(messages: [], nextCursor: nil))
        await vm.loadMore()

        XCTAssertFalse(vm.hasMore, "A nil next cursor exhausts pagination")
        XCTAssertEqual(vm.conversations.count, 1, "No new rows from the empty page")
    }

    func test_givenNextCursor_whenLoadingMore_thenSecondParticipantAppends() async {
        let (vm, service, _) = makeViewModel()
        await service.enqueueFolder(success: DMPage(
            messages: [inbound("m1", from: "user-ada", username: "ada", at: 200)],
            nextCursor: "cursor-2"
        ))
        await service.enqueueUnreadCount(success: 1)
        await vm.load()

        await service.enqueueFolder(success: DMPage(
            messages: [inbound("m2", from: "user-bob", username: "bob", at: 100)],
            nextCursor: nil
        ))
        await vm.loadMore()

        XCTAssertEqual(vm.conversations.map(\.otherUsername), ["ada", "bob"])
        XCTAssertFalse(vm.hasMore)
    }

    // MARK: - Optimistic trash / restore

    func test_givenConversation_whenTrashing_thenDropsRowAndCallsService() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [
            inbound("m1", from: "user-ada", username: "ada", at: 200),
            inbound("m2", from: "user-bob", username: "bob", at: 100)
        ])
        await service.enqueueTrashSuccess()
        await service.enqueueUnreadCount(success: 0)

        await vm.trash(messageID: "m1")

        XCTAssertEqual(vm.conversations.map(\.otherUsername), ["bob"], "The trashed conversation is gone")
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .trash(id: "m1"))))
    }

    func test_givenTrashFails_whenTrashing_thenRestoresSnapshotAndSurfacesError() async {
        let (vm, service, _) = makeViewModel()
        vm.seedForTest(messages: [
            inbound("m1", from: "user-ada", username: "ada", at: 200),
            inbound("m2", from: "user-bob", username: "bob", at: 100)
        ])
        await service.enqueueTrash(failure: TestError.upstream("boom"))

        await vm.trash(messageID: "m1")

        XCTAssertEqual(vm.conversations.count, 2, "The optimistic removal was rolled back")
        XCTAssertEqual(vm.error as? TestError, .upstream("boom"))
    }

    func test_givenRestoreFails_whenRestoring_thenRestoresSnapshotAndSurfacesError() async {
        let (vm, service, _) = makeViewModel()
        vm.folder = .deleted
        vm.seedForTest(messages: [inbound("m1", from: "user-ada", username: "ada", at: 100)])
        await service.enqueueRestore(failure: TestError.upstream("nope"))

        await vm.restore(messageID: "m1")

        XCTAssertEqual(vm.conversations.count, 1, "The optimistic removal was rolled back")
        XCTAssertEqual(vm.error as? TestError, .upstream("nope"))
    }

    // MARK: - Unread count → bus

    func test_givenUnreadCount_whenRefreshing_thenPublishesOnBus() async {
        let (vm, service, bus) = makeViewModel()
        await service.enqueueUnreadCount(success: 4)

        // Subscribe before the refresh so the event is captured.
        let received = expectation(description: "unread event")
        let task = Task {
            for await event in bus.events() {
                if case .unreadCountChanged(let count) = event {
                    XCTAssertEqual(count, 4)
                    received.fulfill()
                    return
                }
            }
        }
        // Give the subscription a beat to register.
        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.refreshUnreadCount()

        await fulfillment(of: [received], timeout: 1.0)
        task.cancel()
        XCTAssertEqual(vm.unreadCount, 4)
    }
}
