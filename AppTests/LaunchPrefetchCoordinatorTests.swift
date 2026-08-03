// LaunchPrefetchCoordinatorTests
//
// Tests the launch-prefetch coordinator (PLAN.md §5, SWR Layer 3). The
// coordinator builds the four/five section view models and warms them
// cache-first at launch. These tests seed each stub service's cache and
// assert that `warmAll()` painted every section from its cache.
//
// The coordinator is constructed via its designated (protocol-typed)
// initializer so no full `AppEnvironment` is needed.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class LaunchPrefetchCoordinatorTests: XCTestCase {

    private func scheduledMessage(id: String) -> Message {
        Message(
            id: id,
            author: MessageFixtures.author(),
            text: "queued",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            visibility: .public,
            digCount: 0,
            didDig: false,
            repostCount: 0,
            replyCount: nil,
            parentID: nil,
            repost: nil,
            scheduledAt: Date().addingTimeInterval(3600)
        )
    }

    private func membership(id: String, name: String) -> UserOrganization {
        UserOrganization(organization: Organization(id: id, name: name), role: .member)
    }

    // MARK: - Warm all four/five sections from cache

    func test_givenSeededCaches_whenWarming_thenAllFourSectionsPaintFromCache() async {
        // Given — every section's cache is primed; the network is left
        // unprogrammed on purpose. A cache-first paint must not depend on the
        // network round-trip succeeding, so the sections render from cache
        // even though the trailing revalidation fails (unprogrammed → throws).
        let lists = StubListsService()
        await lists.setCachedMyLists([ListsFixtures.ownedList(id: "L1", title: "Cached List")])

        let documents = StubDocumentsService()
        await documents.setCachedFolders([DocumentsFixtures.folder(id: "F1", name: "Cached Folder")])
        await documents.setCachedDocuments(
            [DocumentsFixtures.document(id: "D1", title: "Cached Doc")],
            in: nil
        )

        let messages = StubMessagesService()
        await messages.setCachedScheduledPosts([scheduledMessage(id: "s-1")])

        let orgService = StubOrgService()
        let userService = StubUserService()
        userService.setCachedOrganizations([membership(id: "o1", name: "Cached Org")])

        let coordinator = LaunchPrefetchCoordinator(
            lists: lists,
            documents: documents,
            messages: messages,
            orgService: orgService,
            userService: userService
        )

        // When — run the awaitable warm core to a deterministic settle point.
        await coordinator.warmAll()

        // Then — all four/five sections painted their cached content, none
        // showing a blocking spinner.
        XCTAssertEqual(coordinator.listsVM.lists_loaded.map(\.id), ["L1"])
        XCTAssertFalse(coordinator.listsVM.isLoading)

        XCTAssertEqual(coordinator.folderTreeVM.folders.map(\.id), ["F1"])
        XCTAssertFalse(coordinator.folderTreeVM.isLoading)

        XCTAssertEqual(coordinator.documentsListVM.documentsLoaded.map(\.id), ["D1"])
        XCTAssertFalse(coordinator.documentsListVM.isLoading)

        XCTAssertEqual(coordinator.scheduledVM.posts.map(\.id), ["s-1"])
        XCTAssertFalse(coordinator.scheduledVM.isLoading)

        XCTAssertEqual(coordinator.organizationsVM.memberships.map(\.id), ["o1"])
        XCTAssertFalse(coordinator.organizationsVM.isLoading)
    }

    // MARK: - Warm with cold caches revalidates over the network

    func test_givenColdCachesAndNetworkData_whenWarming_thenAllSectionsPaintNetworkData() async {
        // Given — no caches; each section's network load provides its data.
        let lists = StubListsService()
        await lists.enqueueMyLists(success: ListsFixtures.ownedListsPage([
            ListsFixtures.ownedList(id: "L9")
        ]))

        let documents = StubDocumentsService()
        await documents.enqueueFolders(success: [DocumentsFixtures.folder(id: "F9")])
        await documents.enqueueDocuments(success: [DocumentsFixtures.document(id: "D9")])

        let messages = StubMessagesService()
        await messages.enqueueScheduledPosts(success: [scheduledMessage(id: "s-9")])

        let orgService = StubOrgService()
        let userService = StubUserService()
        userService.enqueueOrganizations(success: [membership(id: "o9", name: "Net Org")])

        let coordinator = LaunchPrefetchCoordinator(
            lists: lists,
            documents: documents,
            messages: messages,
            orgService: orgService,
            userService: userService
        )

        // When
        await coordinator.warmAll()

        // Then — each section painted the freshly-loaded network data.
        XCTAssertEqual(coordinator.listsVM.lists_loaded.map(\.id), ["L9"])
        XCTAssertEqual(coordinator.folderTreeVM.folders.map(\.id), ["F9"])
        XCTAssertEqual(coordinator.documentsListVM.documentsLoaded.map(\.id), ["D9"])
        XCTAssertEqual(coordinator.scheduledVM.posts.map(\.id), ["s-9"])
        XCTAssertEqual(coordinator.organizationsVM.memberships.map(\.id), ["o9"])
    }
}
