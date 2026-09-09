// DirectMessagesListViewModelTests
//
// BDD-named tests for the DM conversation-list view model
// (work-consolidation.md G1, G22). Two sources are covered separately:
//
//   • Sent / Deleted still fold a flat folder listing client-side, so the
//     grouping tests run on `.sent` — the Inbox no longer takes that path.
//   • The Inbox reads the server-grouped `conversations(cursor:)` feed.
//
// Covers the required quartet on both, plus pagination, the optimistic
// trash/restore rollback, and the G22 deep-link resolution:
//   - happy: a folder load groups the flat listing into conversations;
//     an inbox load paints rows straight from the server summaries.
//   - invalid input: trashing an id not in the list makes no service call.
//   - upstream failure: a failing load surfaces the error, on both sources.
//   - empty / boundary: an empty page reports an empty list + hasLoadedOnce;
//     a conversation whose newest message predates the first folder page is
//     still listed by the conversations feed.
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

    /// Builds the view model on an explicit folder. `initialFolder` is set in
    /// the initializer, so no unawaited `didSet` reload races the test.
    private func makeViewModel(
        initialFolder: DMFolder = .inbox
    ) -> (DirectMessagesListViewModel, StubDirectMessagesService, DirectMessagesEventBus) {
        let service = StubDirectMessagesService()
        let bus = DirectMessagesEventBus()
        let vm = DirectMessagesListViewModel(
            service: service,
            eventBus: bus,
            currentUserID: { [me] in me },
            initialFolder: initialFolder
        )
        return (vm, service, bus)
    }

    /// A server-grouped conversation row, as `GET /api/dm/conversations`
    /// would project it.
    private func summary(
        pairKey: String,
        with otherId: String,
        username: String,
        unread: Int,
        latest: DirectMessage?
    ) -> DMConversationSummary {
        DMConversationSummary(
            id: pairKey,
            pairKey: pairKey,
            otherUser: other(otherId, username),
            unreadCount: unread,
            latestMessage: latest
        )
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
        // Sent still folds a flat listing client-side; the Inbox does not.
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
        await service.enqueueFolder(success: DMPage(messages: [
            inbound("m3", from: "user-ada", username: "ada", at: 300),
            inbound("m2", from: "user-ada", username: "ada", read: true, at: 200),
            inbound("m1", from: "user-bob", username: "bob", at: 100)
        ], nextCursor: nil))
        await service.enqueueUnreadCount(success: 1)

        await vm.load()

        XCTAssertEqual(vm.conversations.count, 2, "Two distinct participants → two rows")
        XCTAssertEqual(vm.conversations.first?.otherUsername, "ada")
        XCTAssertEqual(vm.conversations.first?.latestMessage?.id, "m3", "Newest message is the preview")
        XCTAssertEqual(vm.conversations.first?.unreadCount, 1, "m3 unread, m2 read")
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    // MARK: - Invalid input (no-op trash of an absent id)

    func test_givenMessageIdNotInList_whenTrashing_thenServiceIsNotCalled() async {
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
        vm.seedForTest(messages: [inbound("m1", from: "user-ada", username: "ada", at: 100)])

        await vm.trash(messageID: "does-not-exist")

        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "Trashing an absent id must not call the service")
        XCTAssertEqual(vm.conversations.count, 1, "The list is untouched")
    }

    // MARK: - Upstream API failure

    func test_givenUpstreamFailure_whenLoading_thenSurfacesErrorAndHasLoadedOnce() async {
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
        await service.enqueueFolder(failure: TestError.upstream("net"))
        await service.enqueueUnreadCount(success: 0)

        await vm.load()

        XCTAssertEqual(vm.error as? TestError, .upstream("net"))
        XCTAssertTrue(vm.conversations.isEmpty)
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    // MARK: - Empty / boundary

    func test_givenEmptyPage_whenLoading_thenReportsEmptyAndHasLoadedOnce() async {
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
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
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
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
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
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
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
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
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
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
        let (vm, service, _) = makeViewModel(initialFolder: .sent)
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
        let (vm, service, _) = makeViewModel(initialFolder: .deleted)
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

    // MARK: - G22: the server-grouped conversations inbox
    //
    // Quartet on the Inbox path, which reads `conversations(cursor:)`
    // instead of collapsing a folder page client-side.

    // Happy

    func test_givenInboxFolder_whenLoading_thenReadsConversationsFeedNotFolderListing() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueConversations(success: DMConversationPage(conversations: [
            summary(
                pairKey: "user-ada:user-me",
                with: "user-ada",
                username: "ada",
                unread: 2,
                latest: inbound("m9", from: "user-ada", username: "ada", at: 900)
            )
        ], nextCursor: nil))
        await service.enqueueUnreadCount(success: 2)

        await vm.load()

        XCTAssertEqual(vm.conversations.map(\.otherUsername), ["ada"])
        XCTAssertEqual(vm.conversations.first?.unreadCount, 2, "The server's count is used verbatim")
        XCTAssertEqual(vm.conversations.first?.latestMessage?.id, "m9")
        let recorded = await service.recorded
        XCTAssertTrue(
            recorded.contains(.init(kind: .conversations(cursor: nil))),
            "The inbox must read the server-grouped feed"
        )
        XCTAssertFalse(
            recorded.contains(.init(kind: .folder(folder: .inbox, cursor: nil))),
            "The inbox must no longer collapse a folder page client-side"
        )
    }

    func test_givenServerUnreadCountOfZero_whenLoadingInbox_thenRowIsNotBadged() async {
        // The server owns the count on this path; nothing re-derives it from
        // the preview message's read state.
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueConversations(success: DMConversationPage(conversations: [
            summary(
                pairKey: "p1",
                with: "user-ada",
                username: "ada",
                unread: 0,
                latest: inbound("m1", from: "user-ada", username: "ada", read: false, at: 100)
            )
        ]))
        await service.enqueueUnreadCount(success: 0)

        await vm.load()

        XCTAssertEqual(vm.conversations.first?.unreadCount, 0)
    }

    // Invalid input

    func test_givenIdNotInConversationsFeed_whenTrashing_thenServiceIsNotCalled() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        vm.seedForTest(conversations: [
            summary(
                pairKey: "p1",
                with: "user-ada",
                username: "ada",
                unread: 1,
                latest: inbound("m1", from: "user-ada", username: "ada", at: 100)
            )
        ])

        await vm.trash(messageID: "not-here")

        let recorded = await service.recorded
        XCTAssertTrue(recorded.isEmpty, "Trashing an absent id must not call the service")
        XCTAssertEqual(vm.conversations.count, 1, "The list is untouched")
    }

    // Upstream failure

    func test_givenConversationsFeedFails_whenLoadingInbox_thenSurfacesErrorAndHasLoadedOnce() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueConversations(failure: TestError.upstream("conv-down"))
        await service.enqueueUnreadCount(success: 0)

        await vm.load()

        XCTAssertEqual(vm.error as? TestError, .upstream("conv-down"))
        XCTAssertTrue(vm.conversations.isEmpty)
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    func test_givenTrashFailsOnConversationRow_whenTrashing_thenRestoresSnapshot() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        vm.seedForTest(conversations: [
            summary(pairKey: "p1", with: "user-ada", username: "ada", unread: 1,
                    latest: inbound("m1", from: "user-ada", username: "ada", at: 200)),
            summary(pairKey: "p2", with: "user-bob", username: "bob", unread: 0,
                    latest: inbound("m2", from: "user-bob", username: "bob", at: 100))
        ])
        await service.enqueueTrash(failure: TestError.upstream("boom"))

        await vm.trash(messageID: "m1")

        XCTAssertEqual(vm.conversations.count, 2, "The optimistic removal was rolled back")
        XCTAssertEqual(vm.error as? TestError, .upstream("boom"))
    }

    // Empty / boundary

    func test_givenEmptyConversationsPage_whenLoadingInbox_thenReportsEmpty() async {
        // The shape the live route actually returned on 2026-09-09:
        // {"items":[],"nextCursor":null}.
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueConversations(success: .empty)
        await service.enqueueUnreadCount(success: 0)

        await vm.load()

        XCTAssertTrue(vm.conversations.isEmpty)
        XCTAssertFalse(vm.hasMore)
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertNil(vm.error)
    }

    func test_givenConversationOlderThanAFolderPage_whenLoadingInbox_thenItIsStillListed() async {
        // The whole point of G22: with client-side grouping, a conversation
        // whose newest message falls off the end of the fetched folder page is
        // invisible. Server-side grouping has no such failure mode — this row
        // is far older than the others and still arrives on page one.
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueConversations(success: DMConversationPage(conversations: [
            summary(pairKey: "p1", with: "user-ada", username: "ada", unread: 0,
                    latest: inbound("recent", from: "user-ada", username: "ada", at: 9_000)),
            summary(pairKey: "p2", with: "user-zed", username: "zed", unread: 1,
                    latest: inbound("ancient", from: "user-zed", username: "zed", at: 1))
        ], nextCursor: nil))
        await service.enqueueUnreadCount(success: 1)

        await vm.load()

        XCTAssertEqual(vm.conversations.map(\.otherUsername), ["ada", "zed"])
        XCTAssertEqual(vm.conversations.last?.latestMessage?.id, "ancient")
    }

    func test_givenRowWithNoDecodableMessage_whenLoadingInbox_thenRowStillListsWithEmptyPreview() async {
        // The populated server shape is unverified, so the decoder is
        // permissive. A row whose message we could not decode must still list
        // rather than vanish or crash the column.
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueConversations(success: DMConversationPage(conversations: [
            summary(pairKey: "p1", with: "user-ada", username: "ada", unread: 3, latest: nil)
        ]))
        await service.enqueueUnreadCount(success: 3)

        await vm.load()

        XCTAssertEqual(vm.conversations.count, 1)
        XCTAssertEqual(vm.conversations.first?.preview, "")
        XCTAssertNil(vm.conversations.first?.latestMessage)
        XCTAssertEqual(vm.conversations.first?.unreadCount, 3)
    }

    // Pagination

    func test_givenConversationsCursor_whenLoadingMore_thenAppendsRowsAndPassesCursor() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueConversations(success: DMConversationPage(conversations: [
            summary(pairKey: "p1", with: "user-ada", username: "ada", unread: 0,
                    latest: inbound("m1", from: "user-ada", username: "ada", at: 200))
        ], nextCursor: "cursor-2"))
        await service.enqueueUnreadCount(success: 0)
        await vm.load()
        XCTAssertTrue(vm.hasMore)

        await service.enqueueConversations(success: DMConversationPage(conversations: [
            summary(pairKey: "p2", with: "user-bob", username: "bob", unread: 0,
                    latest: inbound("m2", from: "user-bob", username: "bob", at: 100))
        ], nextCursor: nil))
        await vm.loadMore()

        XCTAssertEqual(vm.conversations.map(\.otherUsername), ["ada", "bob"])
        XCTAssertFalse(vm.hasMore, "A nil next cursor exhausts pagination")
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .conversations(cursor: "cursor-2"))))
    }

    func test_givenZeroItemConversationsPage_whenLoadingMore_thenClearsHasMore() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueConversations(success: DMConversationPage(conversations: [
            summary(pairKey: "p1", with: "user-ada", username: "ada", unread: 0,
                    latest: inbound("m1", from: "user-ada", username: "ada", at: 200))
        ], nextCursor: "cursor-2"))
        await service.enqueueUnreadCount(success: 0)
        await vm.load()

        await service.enqueueConversations(success: DMConversationPage(conversations: [], nextCursor: nil))
        await vm.loadMore()

        XCTAssertFalse(vm.hasMore)
        XCTAssertEqual(vm.conversations.count, 1, "No new rows from the empty page")
    }

    // MARK: - G22: single-message deep-link resolution

    func test_givenMessageAlreadyInListing_whenResolvingDeepLink_thenAnswersWithoutFetching() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        vm.seedForTest(conversations: [
            summary(pairKey: "p1", with: "user-ada", username: "ada", unread: 1,
                    latest: inbound("m1", from: "user-ada", username: "ada", at: 100))
        ])

        let username = await vm.conversationUsername(forMessageID: "m1")

        XCTAssertEqual(username, "ada")
        let recorded = await service.recorded
        XCTAssertFalse(
            recorded.contains(.init(kind: .message(id: "m1"))),
            "A message already on screen must not cost a round-trip"
        )
    }

    func test_givenUnknownMessageId_whenResolvingDeepLink_thenFetchesAndResolvesUsername() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueMessage(success: inbound("m42", from: "user-zed", username: "zed", at: 500))

        let username = await vm.conversationUsername(forMessageID: "m42")

        XCTAssertEqual(username, "zed")
        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains(.init(kind: .message(id: "m42"))))
    }

    func test_givenFetchFails_whenResolvingDeepLink_thenReturnsNilAndDoesNotErrorTheListing() async {
        // A deep link we can't follow is not a listing failure — the column
        // must not be replaced by an error banner over it.
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueMessage(failure: TestError.upstream("404"))

        let username = await vm.conversationUsername(forMessageID: "gone")

        XCTAssertNil(username)
        XCTAssertNil(vm.error)
    }

    func test_givenMessageWithNoNamedParticipants_whenResolvingDeepLink_thenReturnsNil() async {
        let (vm, service, _) = makeViewModel(initialFolder: .inbox)
        await service.enqueueMessage(success: DirectMessage(
            id: "bare",
            senderId: "user-zed",
            recipientId: me,
            body: "hi",
            createdAt: Date(timeIntervalSince1970: 10)
        ))

        let username = await vm.conversationUsername(forMessageID: "bare")

        XCTAssertNil(username, "No username to open a thread with")
    }
}
