import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `DirectMessagesService` (work-consolidation.md G1). Quartet per
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

    // MARK: - G22: conversations, single message, image upload
    //
    // Routes probed live 2026-09-09, read-only (GET + OPTIONS). The populated
    // conversations shape could not be captured — the shared test account's
    // inbox is empty and writes were not permitted — so the decoder is
    // permissive and these cases pin that tolerance.

    // MARK: conversations — happy

    func test_givenNestedConversations_whenLoading_thenMapsRowsAndHitsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"items":[{"pairKey":"s:r","unreadCount":2,
                   "otherUser":{"id":"s","username":"messenger","displayName":"Messenger"},
                   "lastMessage":\#(dmJSON(id: "m1"))}],
         "nextCursor":"c2"}
        """#)
        let service = DirectMessagesService(api: api)

        let page = try await service.conversations()

        XCTAssertEqual(page.conversations.count, 1)
        XCTAssertEqual(page.conversations.first?.id, "s:r", "pairKey is the row identity")
        XCTAssertEqual(page.conversations.first?.otherUsername, "messenger")
        XCTAssertEqual(page.conversations.first?.unreadCount, 2)
        XCTAssertEqual(page.conversations.first?.latestMessage?.id, "m1")
        XCTAssertEqual(page.conversations.first?.preview, "hi there")
        XCTAssertEqual(page.nextCursor, "c2")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm/conversations")
        XCTAssertEqual(recorded.first?.method, "GET")
    }

    func test_givenFlattenedConversations_whenLoading_thenTreatsTheRowAsItsNewestMessage() async throws {
        // A `GROUP BY pairKey` that returns the newest row per pair.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"items":[\#(dmJSON(id: "m7"))],"nextCursor":null}"#)
        let service = DirectMessagesService(api: api)

        let page = try await service.conversations()

        XCTAssertEqual(page.conversations.first?.latestMessage?.id, "m7")
        XCTAssertEqual(page.conversations.first?.id, "s:r")
        XCTAssertEqual(page.conversations.first?.otherUsername, "messenger",
                       "Falls back to the message's sender when no otherUser is named")
    }

    func test_givenCursor_whenLoadingConversations_thenForwardsIt() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"items":[],"nextCursor":null}"#)
        let service = DirectMessagesService(api: api)

        _ = try await service.conversations(cursor: "c9")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.query["cursor"], "c9")
    }

    // MARK: conversations — invalid / unexpected shape

    func test_givenUnknownConversationKeys_whenLoading_thenRowSurvivesWithFallbackIdentity() async throws {
        // Permissive by design: an unrecognised spelling degrades one field,
        // it does not fail the page — and the row still gets a unique id so
        // two such rows can't collide in a SwiftUI list.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"items":[{"totallyUnknown":"x"},{"alsoUnknown":"y"}],"nextCursor":null}"#)
        let service = DirectMessagesService(api: api)

        let page = try await service.conversations()

        XCTAssertEqual(page.conversations.map(\.id), ["dm-conversation-0", "dm-conversation-1"])
        XCTAssertNil(page.conversations.first?.latestMessage)
        XCTAssertEqual(page.conversations.first?.unreadCount, 0, "An unreported count badges nothing")
        XCTAssertEqual(page.conversations.first?.preview, "")
    }

    // MARK: conversations — upstream failure

    func test_givenServerFailure_whenLoadingConversations_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.conversations()
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: conversations — empty / boundary

    func test_givenEmptyConversations_whenLoading_thenReturnsEmptyPage() async throws {
        // The exact body the live route returned on 2026-09-09.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"items":[],"nextCursor":null}"#)
        let service = DirectMessagesService(api: api)

        let page = try await service.conversations()

        XCTAssertTrue(page.conversations.isEmpty)
        XCTAssertNil(page.nextCursor)
    }

    // MARK: message(id:)

    func test_givenWrappedMessage_whenFetchingById_thenMapsItAndHitsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"message":\#(dmJSON(id: "m5"))}"#)
        let service = DirectMessagesService(api: api)

        let message = try await service.message(id: "m5")

        XCTAssertEqual(message.id, "m5")
        XCTAssertEqual(message.sender?.username, "messenger")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm/m5")
    }

    func test_givenBareMessage_whenFetchingById_thenStillMapsIt() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: dmJSON(id: "m6"))
        let service = DirectMessagesService(api: api)

        let message = try await service.message(id: "m6")

        XCTAssertEqual(message.id, "m6")
    }

    func test_givenNotFound_whenFetchingMessageById_thenThrowsNotFound() async throws {
        // What the live route answered for an unknown id on 2026-09-09.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Message not found."))
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.message(id: "nope")
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Message not found."))
        }
    }

    func test_givenMessageWithNoImages_whenFetchingById_thenImageURLsIsEmptyNotNil() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"id":"m0","senderId":"s","recipientId":"r","body":"plain",
         "createdAt":"2026-07-31T22:20:32.337Z"}
        """#)
        let service = DirectMessagesService(api: api)

        let message = try await service.message(id: "m0")

        XCTAssertTrue(message.imageURLs.isEmpty)
        XCTAssertNil(message.readAt)
    }

    // MARK: uploadImage — happy

    func test_givenValidImage_whenUploading_thenPreparesAndReturnsHostedURL() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.mediaUploadResponse(url: "https://cdn/dm.png"))
        let service = DirectMessagesService(api: api)

        let url = try await service.uploadImage(Fixtures.tinyPNGData)

        XCTAssertEqual(url, "https://cdn/dm.png")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm/images/upload")
        XCTAssertEqual(recorded.first?.method, "POST")
    }

    func test_givenLiveLimits_whenUploading_thenPrepUsesThemNotTheBuiltInConstants() async throws {
        // G14 tail: the prep budget is server-driven, shared with the post
        // composer. This same PNG uploads fine under the default 1.4 MB
        // ceiling (the test above); under an injected 10-byte ceiling prep
        // exhausts its ladder and refuses — which is only possible if the
        // injected limits, not `ImagePrep`'s constants, drove the pipeline.
        let api = StubAPIClient()
        let limits = StubDMContentLimits(value: ContentLimits(
            imageMaxBytes: 10,
            imageMaxPixels: 1,
            imageAcceptedFormats: ["png"],
            videoMaxBytes: 1,
            videoAcceptedFormats: [],
            messageMaxContentLength: 5000
        ))
        let service = DirectMessagesService(api: api, contentLimits: limits)

        do {
            _ = try await service.uploadImage(Fixtures.tinyPNGData)
            XCTFail("Expected the injected byte ceiling to be enforced")
        } catch let error as ImagePrepError {
            XCTAssertEqual(error, .tooLargeAfterAllAttempts)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "Nothing is uploaded when prep can't meet the budget")
    }

    // MARK: uploadImage — invalid input

    func test_givenUndecodableBytes_whenUploading_thenThrowsBeforeAnyRequest() async throws {
        let api = StubAPIClient()
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.uploadImage(Data("not an image".utf8))
            XCTFail("Expected ImagePrepError.undecodable")
        } catch let error as ImagePrepError {
            XCTAssertEqual(error, .undecodable)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "Prep fails before the upload is attempted")
    }

    // MARK: uploadImage — upstream failure

    func test_givenUnverifiedEmailRefusal_whenUploading_thenSurfacesTheServerWordingVerbatim() async throws {
        // Photo sending requires a verified email. There is deliberately no
        // client-side pre-check here — issue #41 owns that gate — so the
        // server's own explanation must reach the UI unrewritten.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "Please verify your email address to send images."))
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.uploadImage(Fixtures.tinyPNGData)
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "Please verify your email address to send images."))
            XCTAssertEqual(error.userFacingMessage, "Please verify your email address to send images.")
        }
    }

    // MARK: send — the documented DM ceilings

    func test_givenNineImageURLs_whenSending_thenRejectsBeforeTheRequest() async throws {
        let api = StubAPIClient()
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.send(
                recipientId: "r",
                body: "hi",
                imageURLs: (0..<9).map { "https://cdn/\($0).png" }
            )
            XCTFail("Expected tooManyImages")
        } catch let error as DirectMessagesError {
            XCTAssertEqual(error, .tooManyImages(limit: 8))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "The cap is enforced before any HTTP call")
    }

    func test_givenExactlyEightImageURLs_whenSending_thenTheRequestIsMade() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"message":\#(dmJSON(id: "m9"))}"#)
        let service = DirectMessagesService(api: api)

        _ = try await service.send(
            recipientId: "r",
            body: "hi",
            imageURLs: (0..<8).map { "https://cdn/\($0).png" }
        )

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm", "Exactly at the cap is allowed")
    }

    func test_givenBodyOverTenThousandCharacters_whenSending_thenRejectsBeforeTheRequest() async throws {
        let api = StubAPIClient()
        let service = DirectMessagesService(api: api)

        do {
            _ = try await service.send(recipientId: "r", body: String(repeating: "a", count: 10_001))
            XCTFail("Expected bodyTooLong")
        } catch let error as DirectMessagesError {
            XCTAssertEqual(error, .bodyTooLong(limit: 10_000))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenExactlyTenThousandCharacters_whenSending_thenTheRequestIsMade() async throws {
        // 10,000 for DMs — deliberately not the post composer's 5,000.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"message":\#(dmJSON(id: "m9"))}"#)
        let service = DirectMessagesService(api: api)

        _ = try await service.send(recipientId: "r", body: String(repeating: "a", count: 10_000))

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/dm")
    }
}

/// Test double serving fixed content limits, so the DM upload's prep budget
/// can be asserted as server-driven (work-consolidation.md G14 tail / G22).
private struct StubDMContentLimits: ContentLimitsProviding {
    let value: ContentLimits
    func limits() async -> ContentLimits { value }
}
