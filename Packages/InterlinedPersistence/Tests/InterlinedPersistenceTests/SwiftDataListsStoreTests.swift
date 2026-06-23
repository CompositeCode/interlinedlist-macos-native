import XCTest
import InterlinedDomain
@testable import InterlinedPersistence

/// BDD-named coverage for `SwiftDataListsStore` (Wave 4.1 / M3 lists cache).
/// Mirrors the `SwiftDataMessageStoreTests` shape: round-trip,
/// second-write-wins, cross-list isolation, clear, and dropped-on-remove
/// semantics.
final class SwiftDataListsStoreTests: XCTestCase {

    // MARK: - Owned-list page

    func test_givenCachedLists_whenReading_thenReturnsListsInOrder() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        let lists = [
            sampleList(id: "a", title: "Alpha"),
            sampleList(id: "b", title: "Beta"),
            sampleList(id: "c", title: "Gamma")
        ]

        // When
        await store.cacheLists(lists)

        // Then
        let cached = await store.cachedLists()
        XCTAssertEqual(cached.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(cached.map(\.title), ["Alpha", "Beta", "Gamma"])
    }

    func test_givenEmptyStore_whenReadingLists_thenReturnsEmpty() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()

        // When / Then
        let cached = await store.cachedLists()
        XCTAssertTrue(cached.isEmpty)
    }

    func test_givenCacheListsTwice_whenReading_thenSecondWriteWins() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        await store.cacheLists([
            sampleList(id: "a"),
            sampleList(id: "b")
        ])

        // When
        await store.cacheLists([sampleList(id: "c")])

        // Then — second write fully supersedes the first.
        let cached = await store.cachedLists()
        XCTAssertEqual(cached.map(\.id), ["c"])
    }

    // MARK: - Single-list by id

    func test_givenUpsertedList_whenReadingByID_thenRoundTripsAllFields() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        let original = OwnedList(
            id: "books",
            title: "Books",
            description: "Read pile",
            visibility: .private,
            schemaDescription: "Title:text, Year:number",
            parentID: "parent-1",
            gitHubSource: GitHubListSource(
                repository: "ada/books",
                path: "data/books.csv",
                branch: "main",
                lastRefreshedAt: Date(timeIntervalSince1970: 1_800_000_000),
                refreshStatus: "ok"
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        // When
        await store.cacheList(original)

        // Then
        let fetched = await store.cachedList(id: "books")
        XCTAssertEqual(fetched, original)
    }

    func test_givenUpsertedTwice_whenReadingByID_thenSecondWriteWins() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        await store.cacheList(sampleList(id: "books", title: "v1"))

        // When
        await store.cacheList(sampleList(id: "books", title: "v2"))

        // Then
        let fetched = await store.cachedList(id: "books")
        XCTAssertEqual(fetched?.title, "v2")
    }

    func test_givenEmptyStore_whenReadingByID_thenReturnsNil() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()

        // When / Then
        let fetched = await store.cachedList(id: "missing")
        XCTAssertNil(fetched)
    }

    func test_givenCacheLists_whenReadingByID_thenAlsoIndexed() async throws {
        // Given — `cacheLists` populates the by-id index too, matching the
        // `SwiftDataMessageStore.replaceTimeline` semantics.
        let store = try SwiftDataListsStore.inMemory()

        // When
        await store.cacheLists([sampleList(id: "a")])

        // Then
        let byID = await store.cachedList(id: "a")
        XCTAssertEqual(byID?.id, "a")
    }

    // MARK: - Cross-list isolation

    func test_givenTwoLists_whenCachingRowsForEach_thenRowsIsolated() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()

        // When
        await store.cacheRows(
            [sampleRow(id: "row-a-1", listID: "list-a", fields: ["Title": .string("First")])],
            of: "list-a"
        )
        await store.cacheRows(
            [sampleRow(id: "row-b-1", listID: "list-b", fields: ["Title": .string("Second")])],
            of: "list-b"
        )

        // Then — each list returns only its own rows.
        let aRows = await store.cachedRows(of: "list-a")
        let bRows = await store.cachedRows(of: "list-b")
        XCTAssertEqual(aRows.map(\.id), ["row-a-1"])
        XCTAssertEqual(bRows.map(\.id), ["row-b-1"])
    }

    func test_givenCacheRowsTwice_whenReading_thenSecondWriteWins() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        await store.cacheRows(
            [sampleRow(id: "r1", listID: "books"), sampleRow(id: "r2", listID: "books")],
            of: "books"
        )

        // When
        await store.cacheRows(
            [sampleRow(id: "r3", listID: "books")],
            of: "books"
        )

        // Then
        let cached = await store.cachedRows(of: "books")
        XCTAssertEqual(cached.map(\.id), ["r3"])
    }

    func test_givenRowsWithDynamicFields_whenRoundTripped_thenFieldsPreserved() async throws {
        // Given — every domain cell-value case round-trips through the codec.
        let store = try SwiftDataListsStore.inMemory()
        let fields: [String: ListCellValue] = [
            "Title": .string("Dune"),
            "Year": .int(1965),
            "Rating": .double(4.5),
            "Read": .bool(true),
            "Notes": .null,
            "Tags": .array([.string("sci-fi"), .string("classic")]),
            "Source": .object(["author": .string("Herbert")])
        ]
        let row = sampleRow(id: "r1", listID: "books", fields: fields)

        // When
        await store.cacheRows([row], of: "books")

        // Then
        let cached = await store.cachedRows(of: "books")
        XCTAssertEqual(cached.first?.fields, fields)
    }

    func test_givenEmptyRows_whenReading_thenReturnsEmpty() async throws {
        // Given — boundary: no rows for a list.
        let store = try SwiftDataListsStore.inMemory()

        // When
        let cached = await store.cachedRows(of: "books")

        // Then
        XCTAssertTrue(cached.isEmpty)
    }

    func test_givenMultipleRows_whenReading_thenPreservesOrder() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        let rows = (0..<5).map { sampleRow(id: "r\($0)", listID: "books") }

        // When
        await store.cacheRows(rows, of: "books")

        // Then
        let cached = await store.cachedRows(of: "books")
        XCTAssertEqual(cached.map(\.id), ["r0", "r1", "r2", "r3", "r4"])
    }

    // MARK: - removeList drops dependents

    func test_givenListWithRows_whenRemoved_thenRowsDroppedToo() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        await store.cacheList(sampleList(id: "books"))
        await store.cacheRows([sampleRow(id: "r1", listID: "books")], of: "books")

        // When
        await store.removeList(id: "books")

        // Then — the list and its rows are gone.
        let list = await store.cachedList(id: "books")
        let rows = await store.cachedRows(of: "books")
        XCTAssertNil(list)
        XCTAssertTrue(rows.isEmpty)
    }

    func test_givenListInOwnedPage_whenRemoved_thenPageIsUpdated() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        await store.cacheLists([
            sampleList(id: "a"),
            sampleList(id: "b"),
            sampleList(id: "c")
        ])

        // When
        await store.removeList(id: "b")

        // Then — the page no longer references the removed list.
        let cached = await store.cachedLists()
        XCTAssertEqual(cached.map(\.id), ["a", "c"])
    }

    func test_givenMissingListId_whenRemoved_thenNoOpAndNoCrash() async throws {
        // Given — boundary: removing a list that was never cached.
        let store = try SwiftDataListsStore.inMemory()
        await store.cacheLists([sampleList(id: "a")])

        // When
        await store.removeList(id: "never-cached")

        // Then — the cache is untouched.
        let cached = await store.cachedLists()
        XCTAssertEqual(cached.map(\.id), ["a"])
    }

    // MARK: - Clear

    func test_givenPopulatedStore_whenCleared_thenEverythingEmpty() async throws {
        // Given
        let store = try SwiftDataListsStore.inMemory()
        await store.cacheLists([sampleList(id: "a"), sampleList(id: "b")])
        await store.cacheRows([sampleRow(id: "r1", listID: "a")], of: "a")

        // When
        await store.clear()

        // Then
        let lists = await store.cachedLists()
        let listA = await store.cachedList(id: "a")
        let rowsA = await store.cachedRows(of: "a")
        XCTAssertTrue(lists.isEmpty)
        XCTAssertNil(listA)
        XCTAssertTrue(rowsA.isEmpty)
    }

    // MARK: - NullListsStore

    func test_givenNullListsStore_whenCalledOnEveryMethod_thenNoOpAndEmpty() async {
        // Given — boundary: the no-op store used in hostile boot conditions.
        let store = NullListsStore()

        // When
        await store.cacheList(OwnedList(id: "a", title: "A"))
        await store.cacheLists([OwnedList(id: "a", title: "A")])
        await store.cacheRows([], of: "a")
        await store.removeList(id: "a")
        await store.clear()

        // Then — every read returns empty / nil.
        let lists = await store.cachedLists()
        let list = await store.cachedList(id: "a")
        let rows = await store.cachedRows(of: "a")
        XCTAssertTrue(lists.isEmpty)
        XCTAssertNil(list)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Helpers

    private func sampleList(
        id: String,
        title: String = "List \(UUID().uuidString)",
        description: String? = nil,
        visibility: Visibility = .private
    ) -> OwnedList {
        OwnedList(
            id: id,
            title: title,
            description: description,
            visibility: visibility,
            schemaDescription: nil,
            parentID: nil,
            gitHubSource: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func sampleRow(
        id: String,
        listID: String,
        fields: [String: ListCellValue] = ["Title": .string("Sample")]
    ) -> ListRow {
        ListRow(
            id: id,
            listID: listID,
            fields: fields,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
