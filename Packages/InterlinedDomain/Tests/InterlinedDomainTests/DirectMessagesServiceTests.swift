import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `DirectMessagesService` (the-gaps.md G1). Quartet per
/// public method: happy + invalid + failure + empty/boundary.
final class DirectMessagesServiceTests: XCTestCase {

    private func dmJSON(id: String, senderId: String = "s", recipientId: String = "r") -> String {
        #"""
        {"id":"\#(id)","pairKey":"s:r","senderId":"\#(senderId)","recipientId":"\#(recipientId)",
         "body":"hi there","imageUrls":["https://cdn/a.png"],
         "createdAt":"2026-07-31T22:20:32.337Z","readAt":null,
         "sender":{"id":"s","username":"messenger","displayName":"Messenger"},
         "recipient":{"id":"r","username":"adron","displayName":"Adron"},
         "preview":"hi there"}
        """#
    }

    // MARK: - folder

    func test_givenInbox_whenLoadingFolder_thenMapsMessagesAndHitsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"items":[\#(dmJSON(id: "m1"))],"nextCursor":"c2"}"#)
        let service = DirectMessagesService(api: api)

        let page = try await service.folder(.inbox)

        XCTAssertEqual(page.messages.map(\.id), ["m1"])
        XCTAssertEqual(page.messages.first?.imageURLs.first?.absoluteString, "https://cdn/a.png")
        XCTAssertEqual(page.nextCursor, "c2")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm")
        XCTAssertEqual(recorded.first?.query["folder"], "inbox")
    }

    func test_givenServerFailure_whenLoadingFolder_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.folder(.sent)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenEmpty_whenLoadingFolder_thenReturnsEmptyPage() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"items":[],"nextCursor":null}"#)
        let service = DirectMessagesService(api: api)

        let page = try await service.folder(.deleted)

        XCTAssertTrue(page.messages.isEmpty)
    }

    // MARK: - thread

    func test_givenThread_whenLoading_thenMapsMessagesAndMetadata() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"items":[\#(dmJSON(id: "m1"))],"olderCursor":null,"isMutual":true,"isBlocked":false,
         "otherUser":{"id":"r","username":"adron","displayName":"Adron"}}
        """#)
        let service = DirectMessagesService(api: api)

        let thread = try await service.thread(username: "adron")

        XCTAssertEqual(thread.messages.map(\.id), ["m1"])
        XCTAssertTrue(thread.isMutual)
        XCTAssertFalse(thread.isBlocked)
        XCTAssertEqual(thread.otherUser?.username, "adron")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm/thread/adron")
    }

    // MARK: - send

    func test_givenBody_whenSending_thenMapsWrappedMessageAndPostsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"message":\#(dmJSON(id: "m9"))}"#)
        let service = DirectMessagesService(api: api)

        let message = try await service.send(recipientId: "r", body: "  hi there  ")

        XCTAssertEqual(message.id, "m9")
        XCTAssertTrue(message.isOutgoing(currentUserId: "s"))
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/dm")
    }

    func test_givenEmptyBodyAndNoImages_whenSending_thenThrowsWithoutRequest() async throws {
        let api = StubAPIClient()
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.send(recipientId: "r", body: "   ")
            XCTFail("Expected emptyMessage")
        } catch let error as DirectMessagesError {
            XCTAssertEqual(error, .emptyMessage)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "An empty message must not hit the network")
    }

    func test_givenIneligibleRecipient_whenSending_thenPropagatesForbidden() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "not mutual followers"))
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.send(recipientId: "r", body: "hi")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "not mutual followers"))
        }
    }

    // MARK: - recipients / unreadCount

    func test_givenRecipients_whenLoading_thenMapsUsers() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"recipients":[{"id":"r","username":"adron","displayName":"Adron"}]}"#)
        let service = DirectMessagesService(api: api)

        let users = try await service.recipients()

        XCTAssertEqual(users.map(\.id), ["r"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm/recipients")
    }

    func test_givenUnreadCount_whenLoading_thenReturnsCount() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"count":4}"#)
        let service = DirectMessagesService(api: api)

        let count = try await service.unreadCount()

        XCTAssertEqual(count, 4)
    }

    // MARK: - read / trash / restore

    func test_givenId_whenMarkingRead_thenPostsReadPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"ok":true}"#)
        let service = DirectMessagesService(api: api)

        try await service.markRead(id: "m1")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/dm/m1/read")
    }

    func test_givenId_whenTrashing_thenPostsTrashPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"ok":true}"#)
        let service = DirectMessagesService(api: api)

        try await service.trash(id: "m1")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm/m1/trash")
    }

    func test_givenId_whenRestoring_thenPostsRestorePath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"ok":true}"#)
        let service = DirectMessagesService(api: api)

        try await service.restore(id: "m1")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm/m1/restore")
    }
}
