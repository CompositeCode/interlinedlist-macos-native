import XCTest
@testable import InterlinedKit

private struct Message: Decodable, Sendable, Equatable {
    let id: String
    let body: String
}

final class PaginationTests: XCTestCase {

    // MARK: - PaginatedDecoder

    func test_givenMessagesEnvelope_whenDecoded_thenReturnsItemsAndPagination() throws {
        // Given — happy path: real-shape envelope, collection key "messages".
        let json = #"""
        {
          "messages": [
            { "id": "m1", "body": "hello" },
            { "id": "m2", "body": "world" }
          ],
          "pagination": { "total": 7, "limit": 2, "offset": 0, "hasMore": true }
        }
        """#

        // When
        let page = try PaginatedDecoder.decode(
            Message.self,
            collectionKey: "messages",
            from: Data(json.utf8)
        )

        // Then
        XCTAssertEqual(page.items, [
            Message(id: "m1", body: "hello"),
            Message(id: "m2", body: "world")
        ])
        XCTAssertEqual(page.pagination, PaginationInfo(total: 7, limit: 2, offset: 0, hasMore: true))
    }

    func test_givenListsEnvelope_whenDecodedWithListsKey_thenWorks() throws {
        // Given — different collection key proves the decoder is generic.
        let json = #"""
        { "lists": [], "pagination": { "total": 0, "limit": 50, "offset": 0, "hasMore": false } }
        """#

        // When
        let page = try PaginatedDecoder.decode(
            Message.self,                       // type is irrelevant when array is empty
            collectionKey: "lists",
            from: Data(json.utf8)
        )

        // Then
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertFalse(page.pagination.hasMore)
    }

    func test_givenMissingCollectionKey_whenDecoded_thenThrowsDecoding() {
        // Invalid input: caller asked for "messages" but body had "lists".
        let json = #"{"lists":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}"#

        XCTAssertThrowsError(
            try PaginatedDecoder.decode(
                Message.self,
                collectionKey: "messages",
                from: Data(json.utf8)
            )
        ) { error in
            guard let apiError = error as? APIError, case .decoding = apiError else {
                return XCTFail("Expected APIError.decoding, got \(error)")
            }
        }
    }

    func test_givenMissingPaginationEnvelope_whenDecoded_thenThrowsDecoding() {
        // Boundary: collection present, pagination absent — server bug class.
        let json = #"{"messages":[]}"#
        XCTAssertThrowsError(
            try PaginatedDecoder.decode(
                Message.self,
                collectionKey: "messages",
                from: Data(json.utf8)
            )
        )
    }

    // MARK: - PageIterator

    func test_givenIteratorWithHasMoreFalse_whenIterated_thenStopsAfterFirstPage() async throws {
        // Happy path: one page, then done.
        let onlyPage = Paginated(
            items: [Message(id: "m1", body: "a"), Message(id: "m2", body: "b")],
            pagination: PaginationInfo(total: 2, limit: 50, offset: 0, hasMore: false)
        )
        let iterator = PageIterator<Message>(pageSize: 50) { _, _ in onlyPage }

        var collected: [Message] = []
        for try await page in iterator {
            collected.append(contentsOf: page)
        }
        XCTAssertEqual(collected.count, 2)
    }

    func test_givenIteratorWithMultiplePages_whenIterated_thenAdvancesOffsetUntilDone() async throws {
        // Happy path: drains across pages, advances offset by items.count.
        let pages: [Paginated<Message>] = [
            Paginated(
                items: [Message(id: "1", body: "a"), Message(id: "2", body: "b")],
                pagination: PaginationInfo(total: 5, limit: 2, offset: 0, hasMore: true)
            ),
            Paginated(
                items: [Message(id: "3", body: "c"), Message(id: "4", body: "d")],
                pagination: PaginationInfo(total: 5, limit: 2, offset: 2, hasMore: true)
            ),
            Paginated(
                items: [Message(id: "5", body: "e")],
                pagination: PaginationInfo(total: 5, limit: 2, offset: 4, hasMore: false)
            )
        ]

        // Use an actor-isolated cursor so the @Sendable closure stays safe.
        actor Cursor { var i = 0; func next() -> Int { defer { i += 1 }; return i } }
        let cursor = Cursor()
        let observedOffsets = OffsetRecorder()

        let iterator = PageIterator<Message>(pageSize: 2) { _, offset in
            await observedOffsets.record(offset)
            let i = await cursor.next()
            return pages[i]
        }

        var collected: [Message] = []
        for try await page in iterator {
            collected.append(contentsOf: page)
        }

        XCTAssertEqual(collected.map(\.id), ["1", "2", "3", "4", "5"])
        let observed = await observedOffsets.snapshot()
        XCTAssertEqual(observed, [0, 2, 4])
    }

    func test_givenEmptyFirstPage_whenIterated_thenStopsImmediately() async throws {
        // Boundary: server returns an empty page.
        let empty = Paginated<Message>(
            items: [],
            pagination: PaginationInfo(total: 0, limit: 50, offset: 0, hasMore: false)
        )
        let iterator = PageIterator<Message>(pageSize: 50) { _, _ in empty }

        var pages = 0
        for try await _ in iterator { pages += 1 }
        XCTAssertEqual(pages, 0)
    }

    func test_givenFetcherFailure_whenIterated_thenPropagatesError() async throws {
        // Upstream API failure: the fetcher throws.
        let iterator = PageIterator<Message>(pageSize: 50) { _, _ in
            throw APIError.unauthorized(serverMessage: "Unauthorized")
        }

        do {
            for try await _ in iterator {}
            XCTFail("Expected error")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        }
    }
}

private actor OffsetRecorder {
    private var offsets: [Int] = []
    func record(_ offset: Int) { offsets.append(offset) }
    func snapshot() -> [Int] { offsets }
}
