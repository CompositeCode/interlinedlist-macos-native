import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the M3 (owned-list) surface on `ListsService`
/// (PLAN.md §1 "Structured lists", §6 M3, §7 testing).
///
/// Public-browse M1 coverage stays in `ListsServiceTests.swift`; this file
/// owns the authenticated CRUD, schema, row, watcher, and connection
/// surfaces. Quartet (happy / invalid / failure / empty-or-boundary) is the
/// floor for every public method.
final class OwnedListsServiceTests: XCTestCase {

    // MARK: - Subscriber gating (create-only — GitHub #40)

    /// Reading your own lists is free on every tier. The published matrix says
    /// a lapsed subscriber keeps existing lists "fully usable", so the gate
    /// must not stand between a free account and its own data.
    func test_givenEntitlementsBlockCreation_whenCallingMyLists_thenReadIsUngatedAndHitsAPI() async throws {
        // Given — an entitlement that blocks list *creation*.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(ids: ["l-1"]))
        let service = ListsService(api: api, entitlements: BlockingEntitlements.shared)

        // When
        let page = try await service.myLists(limit: 20, offset: 0)

        // Then — the read went through untouched by the gate.
        XCTAssertEqual(page.lists.map(\.id), ["l-1"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists")
    }

    func test_givenEntitlementsBlockManagement_whenCreatingList_thenThrowsSubscriberRequiredWithoutHittingAPI() async throws {
        // Given
        let api = StubAPIClient()
        let service = ListsService(api: api, entitlements: BlockingEntitlements.shared)

        // When / Then
        do {
            _ = try await service.create(
                title: "Books",
                description: nil,
                schema: nil,
                parentId: nil,
                isPublic: false
            )
            XCTFail("Expected ListsError.subscriberRequired")
        } catch let error as ListsError {
            XCTAssertEqual(error, .subscriberRequired)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    /// Row writes are explicitly free: *"Adding rows to an existing list is
    /// free, even without a subscription."* Deleting one is the same class of
    /// edit, so the creation gate must not fire here either.
    func test_givenEntitlementsBlockCreation_whenDeletingRow_thenRowWriteIsUngatedAndHitsAPI() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = ListsService(api: api, entitlements: BlockingEntitlements.shared)

        // When
        try await service.deleteRow(listId: "list-1", rowId: "row-1")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/lists/list-1/data/row-1")
    }

    func test_givenPermissiveEntitlements_whenCallingPublicBrowse_thenSubscriberGateDoesNotApply() async throws {
        // Given — even with a blocking entitlement, the public-browse M1
        // routes are reachable: they have no gate.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(ids: ["l-1"]))
        let service = ListsService(api: api, entitlements: BlockingEntitlements.shared)

        // When
        let page = try await service.publicLists(username: "ada", limit: 20, offset: 0)

        // Then — call went through; no `subscriberRequired`.
        XCTAssertEqual(page.lists.map(\.id), ["l-1"])
    }

    // MARK: - myLists

    func test_givenSignedInUserHasLists_whenLoadingMyLists_thenMapsPageAndCursor() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(
            ids: ["list-1", "list-2"],
            total: 40,
            limit: 20,
            offset: 0,
            hasMore: true
        ))
        let service = ListsService(api: api)

        // When
        let page = try await service.myLists(limit: 20, offset: 0)

        // Then
        XCTAssertEqual(page.lists.map(\.id), ["list-1", "list-2"])
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 20)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists")
        XCTAssertEqual(recorded.first?.query["limit"], "20")
    }

    func test_givenEmptyAccount_whenLoadingMyLists_thenReturnsEmptyPage() async throws {
        // Given — boundary: brand-new account with no lists.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(ids: [], hasMore: false))
        let service = ListsService(api: api)

        // When
        let page = try await service.myLists(limit: 20, offset: 0)

        // Then
        XCTAssertTrue(page.lists.isEmpty)
        XCTAssertNil(page.nextOffset)
    }

    func test_givenAPIFailure_whenLoadingMyLists_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "sign in"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.myLists(limit: 20, offset: 0)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "sign in"))
        }
    }

    func test_givenLastPage_whenLoadingMyLists_thenNextOffsetIsNil() async throws {
        // Given — invalid-ish boundary: API says hasMore=false on a non-empty page.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(
            ids: ["l-3"],
            total: 21,
            limit: 20,
            offset: 20,
            hasMore: false
        ))
        let service = ListsService(api: api)

        // When
        let page = try await service.myLists(limit: 20, offset: 20)

        // Then
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    // MARK: - myLists SWR cache

    func test_givenStore_whenLoadingFirstPageOfMyLists_thenWritesThroughToCache() async throws {
        // Given — happy path: a store injected, first page fetched.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(ids: ["list-1", "list-2"]))
        let store = FakeListsStore()
        let service = ListsService(api: api, store: store)

        // When
        _ = try await service.myLists(limit: 20, offset: 0)

        // Then — the first page was written through to the cache.
        let cached = await store.cachedLists()
        XCTAssertEqual(cached.map(\.id), ["list-1", "list-2"])
    }

    func test_givenStore_whenLoadingSubsequentPage_thenDoesNotOverwriteCachedFirstPage() async throws {
        // Given — a cache primed with the first page.
        let store = FakeListsStore()
        await store.cacheLists([sampleOwnedList(id: "first-1"), sampleOwnedList(id: "first-2")])
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedLists(ids: ["page2-1"], offset: 20))
        let service = ListsService(api: api, store: store)

        // When — an offset>0 page must not clobber the cached first page.
        _ = try await service.myLists(limit: 20, offset: 20)

        // Then — cache still holds the first page.
        let cached = await store.cachedLists()
        XCTAssertEqual(cached.map(\.id), ["first-1", "first-2"])
    }

    func test_givenPrimedCacheAndAPIFailure_whenLoadingFirstPage_thenReturnsCachedPage() async throws {
        // Given — upstream API failure with a primed cache.
        let store = FakeListsStore()
        await store.cacheLists([sampleOwnedList(id: "cached-1")])
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = ListsService(api: api, store: store)

        // When
        let page = try await service.myLists(limit: 20, offset: 0)

        // Then — the stale cache is surfaced instead of throwing.
        XCTAssertEqual(page.lists.map(\.id), ["cached-1"])
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    func test_givenEmptyCacheAndAPIFailure_whenLoadingFirstPage_thenThrows() async throws {
        // Given — cold cache and a failing API (nothing to fall back to).
        let store = FakeListsStore()
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: nil))
        let service = ListsService(api: api, store: store)

        // When / Then
        do {
            _ = try await service.myLists(limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: nil))
        }
    }

    func test_givenPrimedCacheAndSubsequentPageFailure_whenLoading_thenThrowsRatherThanServingFirstPage() async throws {
        // Given — boundary: a primed first page, but the failing fetch is for
        // offset>0. The fallback is first-page-only, so it must still throw.
        let store = FakeListsStore()
        await store.cacheLists([sampleOwnedList(id: "cached-1")])
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = ListsService(api: api, store: store)

        // When / Then
        do {
            _ = try await service.myLists(limit: 20, offset: 20)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport(message: "offline"))
        }
    }

    func test_givenPrimedCache_whenReadingCachedMyLists_thenReturnsCacheWithNoNetworkCall() async throws {
        // Given — a primed cache and an API that would fail if called.
        let store = FakeListsStore()
        await store.cacheLists([sampleOwnedList(id: "cached-1")])
        let api = StubAPIClient()
        let service = ListsService(api: api, store: store)

        // When — the cache read must not touch the network.
        let cached = await service.cachedMyLists()

        // Then
        XCTAssertEqual(cached.map(\.id), ["cached-1"])
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenNoStore_whenReadingCachedMyLists_thenReturnsEmpty() async throws {
        // Given — boundary: no store injected.
        let api = StubAPIClient()
        let service = ListsService(api: api)

        // When
        let cached = await service.cachedMyLists()

        // Then
        XCTAssertTrue(cached.isEmpty)
    }

    // MARK: - detail

    func test_givenOwnedListExists_whenLoadingDetail_thenUnwrapsTheDataEnvelope() async throws {
        // Given the real `{ "data": { …, "properties": [...] } }` envelope.
        // `Lists.get` decoded a bare `ListDTO`, so `detail(listId:)` could never
        // decode a live response (GitHub #75) — and the test that said otherwise
        // was asserting against a hand-written bare object.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(
            id: "books",
            title: "Books",
            description: "Read pile",
            isPublic: false,
            parentId: "parent-list",
            properties: Fixtures.listPropertiesJSON
        ))
        let service = ListsService(api: api)

        // When
        let list = try await service.detail(listId: "books")

        // Then
        XCTAssertEqual(list.id, "books")
        XCTAssertEqual(list.title, "Books")
        XCTAssertEqual(list.description, "Read pile")
        XCTAssertEqual(list.visibility, .private)
        XCTAssertEqual(list.parentID, "parent-list")
        // The columns come from `properties` — the field the server actually
        // sends — and keep key and label apart.
        XCTAssertEqual(list.schema?.fields.map(\.key), ["title", "year"])
        XCTAssertEqual(list.schema?.fields.map(\.label), ["Title", "Publication Year"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/books")
    }

    func test_givenIsPublicMissing_whenLoadingDetail_thenDefaultsToPrivate() async throws {
        // Given — boundary: API omits `isPublic`. Authenticated path defaults to private.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(id: "books", isPublic: nil))
        let service = ListsService(api: api)

        // When
        let list = try await service.detail(listId: "books")

        // Then
        XCTAssertEqual(list.visibility, .private)
    }

    func test_givenListNotFound_whenLoadingDetail_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no such list"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.detail(listId: "missing")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no such list"))
        }
    }

    // MARK: - create

    func test_givenTitleAndSchema_whenCreating_thenSendsTheSchemaObjectAndUnwrapsTheEnvelope() async throws {
        // Given — the create answers `{ message, data }` with the stored columns.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(
            id: "new-list",
            title: "Films",
            properties: Fixtures.listPropertiesJSON,
            message: "List created successfully"
        ))
        let service = ListsService(api: api)

        // When
        let list = try await service.create(
            title: "Films",
            description: nil,
            schema: try SchemaDSL.parse("Title:text, Year:number"),
            parentId: nil,
            isPublic: false
        )

        // Then
        XCTAssertEqual(list.id, "new-list")
        XCTAssertEqual(list.title, "Films")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists")

        // And the wire body carries the schema as an **object**. A string here
        // is a flat 400 from the server — "Invalid schema: DSL must be an
        // object" — which is why creating a list with columns never worked
        // (GitHub #85). Asserting the shape is the whole point of this case.
        let body = try XCTUnwrap(recorded.first?.body)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let schema = try XCTUnwrap(json["schema"] as? [String: Any],
                                   "schema must be an object, not a string")
        let fields = try XCTUnwrap(schema["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.map { $0["key"] as? String }, ["Title", "Year"])
        XCTAssertEqual(fields.map { $0["type"] as? String }, ["text", "number"])
    }

    func test_givenNoSchema_whenCreating_thenTheSchemaKeyIsOmittedEntirely() async throws {
        // Boundary. An empty schema is not the same as no schema: sending
        // `{"fields": []}` asks for an explicitly column-less list, where
        // omitting the key lets the server apply its own default.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(id: "bare", title: "Bare"))
        let service = ListsService(api: api)

        _ = try await service.create(
            title: "Bare",
            description: nil,
            schema: ListSchema.empty,
            parentId: nil,
            isPublic: false
        )

        let recorded = await api.recorded
        let body = try XCTUnwrap(recorded.first?.body)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertNil(json["schema"], "an empty schema sends no schema key at all")
    }

    func test_givenEmptyTitle_whenCreating_thenAPIRejection() async throws {
        // Given — boundary: empty title. The domain forwards as-is; server validates.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "title required"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.create(
                title: "",
                description: nil,
                schema: nil,
                parentId: nil,
                isPublic: false
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "title required"))
        }
    }

    func test_givenAPIFailure_whenCreating_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.create(
                title: "X",
                description: nil,
                schema: nil,
                parentId: nil,
                isPublic: false
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - update

    func test_givenChanges_whenUpdating_thenPUTsAndReturnsUpdatedList() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(id: "books", title: "Books v2", message: "List updated"))
        let service = ListsService(api: api)

        // When
        let list = try await service.update(
            listId: "books",
            title: "Books v2",
            description: nil,
            isPublic: true,
            parentId: nil
        )

        // Then
        XCTAssertEqual(list.title, "Books v2")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books")
    }

    func test_givenAllFieldsNil_whenUpdating_thenStillIssuesPut() async throws {
        // Given — boundary: a no-op update body still hits the endpoint.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(id: "books"))
        let service = ListsService(api: api)

        // When
        _ = try await service.update(
            listId: "books",
            title: nil,
            description: nil,
            isPublic: nil,
            parentId: nil
        )

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
    }

    func test_givenUpdateAPIFailure_whenUpdating_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "not owner"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.update(
                listId: "books",
                title: "X",
                description: nil,
                isPublic: nil,
                parentId: nil
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "not owner"))
        }
    }

    // MARK: - delete

    func test_givenListId_whenDeleting_thenIssuesDelete() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = ListsService(api: api)

        // When
        try await service.delete(listId: "books")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books")
    }

    func test_givenDeleteAPIFailure_whenDeleting_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "gone"))
        let service = ListsService(api: api)

        // When / Then
        do {
            try await service.delete(listId: "missing")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "gone"))
        }
    }

    // MARK: - schema (read)

    func test_givenCapturedSchemaPayload_whenLoading_thenMapsEveryColumnFacet() async throws {
        // Given the **captured** `GET /api/lists/[id]/schema` payload. The
        // previous fixture was `{"schema": "Title:text, Year:number"}` — a shape
        // the server has never sent; the test passed and the feature did not
        // work (GitHub #85).
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listSchemaEnvelope)
        let service = ListsService(api: api)

        // When
        let schema = try await service.schema(of: "books")

        // Then — key and label are separate, and the metadata the server has
        // always stored finally arrives.
        XCTAssertEqual(schema.orderedFields.map(\.key), ["title", "year", "status"])
        XCTAssertEqual(schema.orderedFields.map(\.label), ["Title", "Publication Year", "Status"])
        XCTAssertEqual(schema.orderedFields.map(\.type), [.text, .number, .select])

        let title = try XCTUnwrap(schema.field(key: "title"))
        XCTAssertEqual(title.isRequired, true)
        XCTAssertEqual(title.helpText, "What is it called?")
        XCTAssertEqual(title.placeholder, "e.g. Dune")
        XCTAssertEqual(title.validation?.minLength, 2)
        XCTAssertEqual(title.validation?.maxLength, 80)
        XCTAssertEqual(title.validation?.pattern, "^[A-Za-z].*$")

        let year = try XCTUnwrap(schema.field(key: "year"))
        XCTAssertEqual(year.validation?.min, 1000)
        XCTAssertEqual(year.validation?.max, 2100)

        // The select column's options arrive under both spellings live; either
        // alone must be enough.
        let status = try XCTUnwrap(schema.field(key: "status"))
        XCTAssertEqual(status.enumValues, ["todo", "doing", "done"])
        XCTAssertEqual(status.defaultValue, .string("todo"))

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/schema")
    }

    func test_givenUnknownColumnType_whenLoadingSchema_thenDegradesToTextRatherThanFailing() async throws {
        // Invalid input from upstream. A column type the client has never heard
        // of must not take out the whole schema — and with it the row table —
        // so it maps to `.text`, the editor that can display anything.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listSchemaEnvelope(fields: [
            (key: "title", type: "text", label: "Title"),
            (key: "colour", type: "colour-picker-2027", label: "Colour")
        ]))
        let service = ListsService(api: api)

        let schema = try await service.schema(of: "books")

        XCTAssertEqual(schema.fields.map(\.key), ["title", "colour"])
        XCTAssertEqual(schema.field(key: "colour")?.type, .text)
    }

    func test_givenEmptyFieldList_whenLoadingSchema_thenSchemaIsEmptyNotAFailure() async throws {
        // Boundary: a list with no columns yet. The live route answers
        // `{"data":{"name":"New list","fields":[]}}` for exactly this.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listSchemaEnvelope(fields: []))
        let service = ListsService(api: api)

        let schema = try await service.schema(of: "books")

        XCTAssertEqual(schema, .empty)
    }

    func test_givenAPIFailure_whenLoadingSchema_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "no access"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.schema(of: "books")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "no access"))
        }
    }

    // MARK: - schema (write)

    func test_givenSchema_whenUpdatingSchema_thenSendsAnObjectAndReadsBackTheStoredColumns() async throws {
        // Given — the write answers `{ message, data: { …, properties[] } }`.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(
            id: "books",
            properties: Fixtures.listPropertiesJSON,
            message: "Schema updated successfully"
        ))
        let service = ListsService(api: api)
        let schema = ListSchema(fields: [
            SchemaField(name: "Title", type: .text),
            SchemaField(name: "Year", type: .number)
        ])

        // When
        let saved = try await service.updateSchema(of: "books", schema: schema, force: false)

        // Then — the result comes from `properties`, so key and label are the
        // server's, not the ones we sent.
        XCTAssertEqual(saved.fields.map(\.key), ["title", "year"])
        XCTAssertEqual(saved.fields.map(\.label), ["Title", "Publication Year"])

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/schema")
        XCTAssertNil(recorded.first?.query["force"], "a first save never forces")

        // The body carries a schema **object**, not the DSL string that the
        // server rejects.
        let body = try XCTUnwrap(recorded.first?.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["schema"] as? [String: Any], "schema must be an object")
    }

    func test_givenDestructiveRejection_whenUpdatingSchema_thenSurfacesTheConfirmationError() async throws {
        // Upstream failure. The server refuses to drop a column that still holds
        // row data with a 400 — which is a question, not a malfunction — so it
        // must not reach the UI as a bare "Bad Request".
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(
            serverMessage: "Removing these columns would delete existing data."
        ))
        let service = ListsService(api: api)

        do {
            _ = try await service.updateSchema(
                of: "books",
                schema: ListSchema(fields: [SchemaField(name: "Title", type: .text)]),
                force: false
            )
            XCTFail("Expected ListsError.schemaChangeWouldLoseData")
        } catch let error as ListsError {
            guard case .schemaChangeWouldLoseData(let message) = error else {
                return XCTFail("Expected .schemaChangeWouldLoseData, got \(error)")
            }
            XCTAssertEqual(message, "Removing these columns would delete existing data.")
        }
    }

    func test_givenForceRequested_whenUpdatingSchema_thenTheQueryCarriesIt() async throws {
        // And with the user's confirmation the same call goes out with `force`,
        // so a 400 after that is a real failure rather than the same question
        // asked twice.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(
            id: "books",
            properties: Fixtures.listPropertiesJSON
        ))
        let service = ListsService(api: api)

        _ = try await service.updateSchema(
            of: "books",
            schema: ListSchema(fields: [SchemaField(name: "Title", type: .text)]),
            force: true
        )

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.query["force"], "true")
    }

    func test_givenEmptySchema_whenUpdatingSchema_thenStillIssuesThePut() async throws {
        // Boundary: clearing every column is a legitimate request. It is also
        // the maximally destructive one, so it must still go through the
        // unforced path first.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(id: "books", properties: "[]"))
        let service = ListsService(api: api)

        let result = try await service.updateSchema(of: "books", schema: .empty, force: false)

        XCTAssertEqual(result, .empty)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
    }

    // MARK: - refresh

    func test_givenGitHubBackedList_whenRefreshing_thenReturnsFreshList() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listEnvelope(id: "gh-list"))
        let service = ListsService(api: api)

        // When
        let list = try await service.refresh(listId: "gh-list")

        // Then
        XCTAssertEqual(list.id, "gh-list")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/gh-list/refresh")
    }

    func test_givenRefreshAPIFailure_whenRefreshing_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "no source"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.refresh(listId: "gh-list")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "no source"))
        }
    }

    // MARK: - rows

    func test_givenListHasRows_whenLoadingRows_thenMapsPageAndCursor() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedRows(
            ids: ["row-1", "row-2"],
            total: 5,
            limit: 20,
            offset: 0,
            hasMore: false
        ))
        let service = ListsService(api: api)

        // When
        let page = try await service.rows(of: "books", limit: 20, offset: 0)

        // Then
        XCTAssertEqual(page.rows.map(\.id), ["row-1", "row-2"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/data")
    }

    func test_givenNoRows_whenLoadingRows_thenReturnsEmptyPage() async throws {
        // Given — boundary: empty list.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedRows(ids: [], hasMore: false))
        let service = ListsService(api: api)

        // When
        let page = try await service.rows(of: "books", limit: 20, offset: 0)

        // Then
        XCTAssertTrue(page.rows.isEmpty)
    }

    func test_givenRowsAPIFailure_whenLoadingRows_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.rows(of: "books", limit: 20, offset: 0)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport(message: "offline"))
        }
    }

    // MARK: - row by id

    func test_givenRowId_whenLoadingRow_thenMapsCells() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listRowEnvelope(id: "row-7"))
        let service = ListsService(api: api)

        // When
        let row = try await service.row(listId: "books", rowId: "row-7")

        // Then
        XCTAssertEqual(row.id, "row-7")
        XCTAssertEqual(row.fields["Title"], .string("Dune"))
        XCTAssertEqual(row.fields["Year"], .int(1965))
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/data/row-7")
    }

    func test_givenRowNotFound_whenLoadingRow_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "gone"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.row(listId: "books", rowId: "missing")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "gone"))
        }
    }

    // MARK: - row GitHub-backing projection (ListRowDTO → ListRow)

    func test_givenGitHubSyncedRowDTO_whenMapped_thenCarriesSourceRepoAndIsBacked() {
        // Happy path: a synced row carries source + repo; both project through
        // and `isGitHubBacked` is true so the UI can route to the issue flow.
        let dto = ListRowDTO(
            id: "r1",
            listId: "L1",
            rowData: [:],
            source: "github",
            githubRepo: "CompositeCode/interlinedlist"
        )

        let row = ListRow(from: dto)

        XCTAssertEqual(row.source, "github")
        XCTAssertEqual(row.githubRepo, "CompositeCode/interlinedlist")
        XCTAssertTrue(row.isGitHubBacked)
    }

    func test_givenNativeRowDTO_whenMapped_thenNotGitHubBacked() {
        // Boundary: a native row omits both markers; projection keeps them nil
        // and `isGitHubBacked` is false so native Add Row stays available.
        let dto = ListRowDTO(id: "r1", listId: "L1", rowData: ["Title": .string("Dune")])

        let row = ListRow(from: dto)

        XCTAssertNil(row.source)
        XCTAssertNil(row.githubRepo)
        XCTAssertFalse(row.isGitHubBacked)
    }

    func test_givenSourceGithubButNoRepo_whenMapped_thenStillBacked() {
        // Either marker alone suffices: a `source: "github"` with no repo slug
        // is still recognised as backed (case-insensitive).
        let dto = ListRowDTO(id: "r1", listId: "L1", rowData: [:], source: "GitHub")

        let row = ListRow(from: dto)

        XCTAssertTrue(row.isGitHubBacked)
        XCTAssertNil(row.githubRepo)
    }

    // MARK: - row CRUD

    func test_givenRowData_whenCreatingRow_thenPostsAndMapsResponse() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listRowEnvelope(id: "row-new"))
        let service = ListsService(api: api)

        // When
        let row = try await service.createRow(
            listId: "books",
            data: ["Title": .string("Dune"), "Year": .int(1965)]
        )

        // Then
        XCTAssertEqual(row.id, "row-new")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/data")
    }

    func test_givenEmptyRowData_whenCreatingRow_thenStillPosts() async throws {
        // Given — boundary: empty row data; the API accepts it.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listRowEnvelope(id: "row-empty"))
        let service = ListsService(api: api)

        // When
        let row = try await service.createRow(listId: "books", data: [:])

        // Then
        XCTAssertEqual(row.id, "row-empty")
    }

    func test_givenCreateRowAPIFailure_whenCreatingRow_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "schema mismatch"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.createRow(listId: "books", data: ["Title": .string("x")])
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "schema mismatch"))
        }
    }

    func test_givenUpdate_whenUpdatingRow_thenPutsAndMapsResponse() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listRowEnvelope(id: "row-7"))
        let service = ListsService(api: api)

        // When
        let row = try await service.updateRow(
            listId: "books",
            rowId: "row-7",
            data: ["Year": .int(1966)]
        )

        // Then
        XCTAssertEqual(row.id, "row-7")
        let recorded = await api.recorded
        // PUT, not PATCH — PATCH is 405 live (work-consolidation.md §1c · V3).
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/data/row-7")
    }

    func test_givenUpdateRowAPIFailure_whenUpdatingRow_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "viewer"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.updateRow(
                listId: "books",
                rowId: "row-7",
                data: ["Year": .int(1)]
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "viewer"))
        }
    }

    func test_givenRowId_whenDeletingRow_thenIssuesDelete() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = ListsService(api: api)

        // When
        try await service.deleteRow(listId: "books", rowId: "row-7")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/data/row-7")
    }

    func test_givenDeleteRowAPIFailure_whenDeletingRow_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no row"))
        let service = ListsService(api: api)

        // When / Then
        do {
            try await service.deleteRow(listId: "books", rowId: "row-7")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no row"))
        }
    }

    // MARK: - watchers

    func test_givenListHasWatchers_whenLoadingWatchers_thenMapsRoles() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchersEnvelope([
            (userId: "u-1", role: "manager"),
            (userId: "u-2", role: "collaborator"),
            (userId: "u-3", role: "watcher")
        ]))
        let service = ListsService(api: api)

        // When
        let watchers = try await service.watchers(of: "books")

        // Then
        XCTAssertEqual(watchers.map(\.userId), ["u-1", "u-2", "u-3"])
        XCTAssertEqual(watchers.map(\.role), [.owner, .editor, .viewer])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/watchers")
    }

    func test_givenListHasNoWatchers_whenLoadingWatchers_thenReturnsEmptyArray() async throws {
        // Given — boundary: a brand-new list nobody has shared with.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchersEnvelope([]))
        let service = ListsService(api: api)

        // When
        let watchers = try await service.watchers(of: "books")

        // Then
        XCTAssertTrue(watchers.isEmpty)
    }

    func test_givenWatchersAPIFailure_whenLoadingWatchers_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "viewer"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.watchers(of: "books")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "viewer"))
        }
    }

    func test_givenWatcherWithUnknownRole_whenLoadingWatchers_thenPreservesRoleAsOther() async throws {
        // Given — boundary: an unknown role string preserves under `.other`.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchersEnvelope([(userId: "u-1", role: "admin")]))
        let service = ListsService(api: api)

        // When
        let watchers = try await service.watchers(of: "books")

        // Then
        XCTAssertEqual(watchers.first?.role, .other("admin"))
    }

    // MARK: - watcher status

    func test_givenCallerIsViewer_whenLoadingMyStatus_thenIsWatchingTrueAndRoleViewer() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watcherStatusEnvelope(isWatching: true, role: "viewer"))
        let service = ListsService(api: api)

        // When
        let status = try await service.myWatcherStatus(of: "books")

        // Then
        XCTAssertTrue(status.isWatching)
        XCTAssertEqual(status.role, .viewer)
    }

    func test_givenCallerNotWatching_whenLoadingMyStatus_thenIsWatchingFalseAndRoleNil() async throws {
        // Given — boundary: caller is not a watcher; role omitted.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watcherStatusEnvelope(isWatching: false, role: nil))
        let service = ListsService(api: api)

        // When
        let status = try await service.myWatcherStatus(of: "books")

        // Then
        XCTAssertFalse(status.isWatching)
        XCTAssertNil(status.role)
    }

    func test_givenMyStatusAPIFailure_whenLoadingMyStatus_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "gone"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.myWatcherStatus(of: "books")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "gone"))
        }
    }

    // MARK: - set / remove watcher

    func test_givenUserAndRole_whenSettingWatcher_thenPutsAndMapsResponse() async throws {
        // Given — the live route answers `{ role }`, not the watcher row.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.setWatcherRoleEnvelope(role: "collaborator"))
        let service = ListsService(api: api)

        // When
        let watcher = try await service.setWatcher(
            listId: "books",
            userId: "u-9",
            role: .editor
        )

        // Then
        XCTAssertEqual(watcher.userId, "u-9")
        XCTAssertEqual(watcher.role, .editor)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/watchers/u-9")
    }

    func test_givenSetWatcherRejectedAsNonSubscriber_whenSettingWatcher_thenThrowsSubscriberRequired() async throws {
        // Given — role changes are subscriber-gated server-side, so a free
        // owner's 403 must reach the UI as the upsell case, not a raw HTTP
        // error (work-consolidation.md G23).
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "Subscribe to share lists."))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.setWatcher(
                listId: "books",
                userId: "u-9",
                role: .editor
            )
            XCTFail("Expected ListsError.subscriberRequired")
        } catch let error as ListsError {
            XCTAssertEqual(error, .subscriberRequired)
        }
    }

    func test_givenSetWatcherAPIFailure_whenSettingWatcher_thenThrows() async throws {
        // Given — a non-403 failure still surfaces as the raw `APIError`.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no such list"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.setWatcher(
                listId: "books",
                userId: "u-9",
                role: .editor
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no such list"))
        }
    }

    func test_givenWatcherId_whenRemovingWatcher_thenIssuesDelete() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = ListsService(api: api)

        // When
        try await service.removeWatcher(listId: "books", userId: "u-9")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/watchers/u-9")
    }

    func test_givenRemoveWatcherAPIFailure_whenRemovingWatcher_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "not a watcher"))
        let service = ListsService(api: api)

        // When / Then
        do {
            try await service.removeWatcher(listId: "books", userId: "u-9")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "not a watcher"))
        }
    }

    // MARK: - connections

    func test_givenConnectionsExist_whenLoadingAll_thenMapsEveryEdge() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.connectionsEnvelope(["c-1", "c-2"]))
        let service = ListsService(api: api)

        // When
        let connections = try await service.connections(of: nil)

        // Then
        XCTAssertEqual(connections.map(\.id), ["c-1", "c-2"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/connections")
    }

    func test_givenConnectionsExist_whenFilteringByList_thenReturnsOnlyConnected() async throws {
        // Given — three edges; the focused list participates in only one.
        let api = StubAPIClient()
        let json = """
        { "connections": [
            \(Fixtures.connectionObject(id: "c-1", fromListId: "books", toListId: "films")),
            \(Fixtures.connectionObject(id: "c-2", fromListId: "songs", toListId: "albums")),
            \(Fixtures.connectionObject(id: "c-3", fromListId: "albums", toListId: "books"))
        ] }
        """
        await api.enqueue(json: json)
        let service = ListsService(api: api)

        // When
        let connections = try await service.connections(of: "books")

        // Then — only the edges involving `books`.
        XCTAssertEqual(connections.map(\.id), ["c-1", "c-3"])
    }

    func test_givenNoConnections_whenLoadingAll_thenReturnsEmptyArray() async throws {
        // Given — boundary: nothing connected yet.
        let api = StubAPIClient()
        await api.enqueue(json: """
        { "connections": [] }
        """)
        let service = ListsService(api: api)

        // When
        let connections = try await service.connections(of: nil)

        // Then
        XCTAssertTrue(connections.isEmpty)
    }

    func test_givenConnectionsAPIFailure_whenLoadingConnections_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "sign in"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.connections(of: nil)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "sign in"))
        }
    }

    func test_givenTwoLists_whenAddingConnection_thenPostsAndMapsResponse() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.connectionObject(id: "c-new"))
        let service = ListsService(api: api)

        // When
        let connection = try await service.addConnection(
            fromListId: "books",
            toListId: "films",
            label: "based on"
        )

        // Then
        XCTAssertEqual(connection.id, "c-new")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/connections")
    }

    func test_givenAddConnectionAPIFailure_whenAddingConnection_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "cycle"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.addConnection(
                fromListId: "a",
                toListId: "a",
                label: nil
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "cycle"))
        }
    }

    func test_givenConnectionId_whenRemovingConnection_thenIssuesDelete() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = ListsService(api: api)

        // When
        try await service.removeConnection(connectionId: "c-1")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/lists/connections/c-1")
    }

    func test_givenRemoveConnectionAPIFailure_whenRemovingConnection_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "gone"))
        let service = ListsService(api: api)

        // When / Then
        do {
            try await service.removeConnection(connectionId: "missing")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "gone"))
        }
    }
}

// MARK: - Test support

/// An `EntitlementsService` whose `canManageLists` is forced `false` via
/// the `init(customerStatus:canManageLists:)` test seam. The M3 production
/// default is permissive (see `EntitlementsService.canManageLists`); these
/// tests use the override to exercise the `subscriberRequired` failure
/// path so the gate's wiring is verified now rather than waiting on M6.
enum BlockingEntitlements {
    /// A blocking entitlements value — `canManageLists == false`.
    static let shared = EntitlementsService(customerStatus: .free, canManageLists: false)
}

extension OwnedListsServiceTests {
    /// A minimal `OwnedList` for the SWR-cache tests (only `id` matters to the
    /// assertions, which check membership/order by id).
    func sampleOwnedList(id: String) -> OwnedList {
        OwnedList(id: id, title: "List \(id)", visibility: .private)
    }
}

/// In-memory `ListsStore` double for the `ListsService` SWR cache tests. Only
/// the owned-lists-page surface is exercised here; the row / by-id / remove
/// paths are no-ops sufficient for these tests. An `actor` for Swift 6 safety.
private actor FakeListsStore: ListsStore {
    private var lists: [OwnedList] = []

    func cachedLists() async -> [OwnedList] { lists }
    func cacheLists(_ lists: [OwnedList]) async { self.lists = lists }
    func cachedList(id: String) async -> OwnedList? { lists.first { $0.id == id } }
    func cacheList(_ list: OwnedList) async {}
    func removeList(id: String) async { lists.removeAll { $0.id == id } }
    func cachedRows(of listId: String) async -> [ListRow] { [] }
    func cacheRows(_ rows: [ListRow], of listId: String) async {}
    func clear() async { lists.removeAll() }
}

// MARK: - Watching a public list (GitHub #44 / G32)
//
// The Watch button on someone else's profile. Same route as `addWatcher`, taking
// its *self-subscribe* branch by omitting `userId` — and that branch is
// deliberately free: the subscription gates granting someone *else* access, not
// following a list that is already public to you.

extension OwnedListsServiceTests {

    // Happy path

    func test_givenAPublicList_whenWatching_thenPostsWithoutAUserId() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"watching":true}"#)
        let service = ListsService(api: api)

        try await service.watch(listId: "L1")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/L1/watchers")
        // The body must carry no `userId` — that is the whole difference between
        // "subscribe me" and "grant that person access". `StubAPIClient` does not
        // record request bodies on this branch, so the shape is asserted at the
        // kit level instead; the empty-id guard below covers the confusion this
        // could otherwise cause.
    }

    // Free on every tier

    func test_givenAFreeAccount_whenWatching_thenItIsNotGated() async throws {
        // Gating this would make the Watch button on a public profile an upsell
        // for something the web gives away.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"watching":true}"#)
        let service = ListsService(api: api, entitlements: EntitlementsService(customerStatus: .free))

        try await service.watch(listId: "L1")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1, "the call is made, not refused")
    }

    // Upstream failure

    func test_givenTheServerRefuses_whenWatching_thenTheErrorPropagates() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = ListsService(api: api)

        do {
            try await service.watch(listId: "L1")
            XCTFail("Expected the failure to propagate")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // Boundary — addWatcher's empty-id guard still holds, so the two intents
    // cannot be confused by accident

    func test_givenAnEmptyUserId_whenAddingAWatcher_thenItIsRefusedRatherThanBecomingASelfSubscribe() async throws {
        let api = StubAPIClient()
        let service = ListsService(api: api)

        do {
            try await service.addWatcher(listId: "L1", userId: "   ", role: .viewer, notify: false)
            XCTFail("Expected ListsError.invalidWatcher")
        } catch let error as ListsError {
            XCTAssertEqual(error, .invalidWatcher)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "and no round-trip was spent finding out")
    }
}
