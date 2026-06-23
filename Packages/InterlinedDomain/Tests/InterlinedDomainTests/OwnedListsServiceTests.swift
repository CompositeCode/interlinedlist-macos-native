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

    // MARK: - Subscriber gating (defensive M3 gate)

    func test_givenEntitlementsBlockManagement_whenCallingMyLists_thenThrowsSubscriberRequiredWithoutHittingAPI() async throws {
        // Given — a manage-blocking entitlements stub.
        let api = StubAPIClient()
        let service = ListsService(api: api, entitlements: BlockingEntitlements.shared)

        // When / Then
        do {
            _ = try await service.myLists(limit: 20, offset: 0)
            XCTFail("Expected ListsError.subscriberRequired")
        } catch let error as ListsError {
            XCTAssertEqual(error, .subscriberRequired)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "Gated calls must not hit the API.")
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

    func test_givenEntitlementsBlockManagement_whenDeletingRow_thenThrowsSubscriberRequiredWithoutHittingAPI() async throws {
        // Given — covers a void-returning write to confirm the gate fires
        // on every M3 method, not just the value-returning ones.
        let api = StubAPIClient()
        let service = ListsService(api: api, entitlements: BlockingEntitlements.shared)

        // When / Then
        do {
            try await service.deleteRow(listId: "list-1", rowId: "row-1")
            XCTFail("Expected ListsError.subscriberRequired")
        } catch let error as ListsError {
            XCTAssertEqual(error, .subscriberRequired)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
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

    // MARK: - detail

    func test_givenOwnedListExists_whenLoadingDetail_thenMapsAllFields() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listObject(
            id: "books",
            title: "Books",
            description: "Read pile",
            isPublic: false,
            schema: "Title:text, Year:number",
            parentId: "parent-list"
        ))
        let service = ListsService(api: api)

        // When
        let list = try await service.detail(listId: "books")

        // Then
        XCTAssertEqual(list.id, "books")
        XCTAssertEqual(list.title, "Books")
        XCTAssertEqual(list.description, "Read pile")
        XCTAssertEqual(list.visibility, .private)
        XCTAssertEqual(list.schemaDescription, "Title:text, Year:number")
        XCTAssertEqual(list.parentID, "parent-list")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/books")
    }

    func test_givenIsPublicMissing_whenLoadingDetail_thenDefaultsToPrivate() async throws {
        // Given — boundary: API omits `isPublic`. Authenticated path defaults to private.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listObject(id: "books", isPublic: nil))
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

    func test_givenTitleAndSchema_whenCreating_thenPOSTsListAndMapsResponse() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listObject(id: "new-list", title: "Films"))
        let service = ListsService(api: api)

        // When
        let list = try await service.create(
            title: "Films",
            description: nil,
            schema: "Title:text, Year:number",
            parentId: nil,
            isPublic: false
        )

        // Then
        XCTAssertEqual(list.id, "new-list")
        XCTAssertEqual(list.title, "Films")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists")
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
        await api.enqueue(json: Fixtures.listObject(id: "books", title: "Books v2"))
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
        await api.enqueue(json: Fixtures.listObject(id: "books"))
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

    func test_givenValidDSL_whenLoadingSchema_thenParsesIntoFields() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listSchemaEnvelope("Title:text, Year:number"))
        let service = ListsService(api: api)

        // When
        let schema = try await service.schema(of: "books")

        // Then
        XCTAssertEqual(schema.fields.map(\.name), ["Title", "Year"])
        XCTAssertEqual(schema.fields.map(\.type), [.text, .number])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/schema")
    }

    func test_givenMalformedDSL_whenLoadingSchema_thenThrowsMalformedSchema() async throws {
        // Given — invalid-input case at the domain boundary.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listSchemaEnvelope("Bogus without colon"))
        let service = ListsService(api: api)

        // When / Then
        do {
            _ = try await service.schema(of: "books")
            XCTFail("Expected ListsError.malformedSchema")
        } catch let error as ListsError {
            guard case .malformedSchema(let raw, _) = error else {
                return XCTFail("Expected .malformedSchema, got \(error)")
            }
            XCTAssertEqual(raw, "Bogus without colon")
        }
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

    func test_givenSchema_whenUpdatingSchema_thenSerializesAndReparsesResult() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listSchemaEnvelope("Title:text, Year:number"))
        let service = ListsService(api: api)
        let schema = ListSchema(fields: [
            SchemaField(name: "Title", type: .text),
            SchemaField(name: "Year", type: .number)
        ])

        // When
        let reparsed = try await service.updateSchema(of: "books", schema: schema)

        // Then
        XCTAssertEqual(reparsed, schema)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/lists/books/schema")
    }

    func test_givenEmptySchema_whenUpdatingSchema_thenServerDSLIsEmpty() async throws {
        // Given — boundary: serializing an empty schema yields `""`; the
        // request is still issued, and the server's reply drives the parse.
        // The parser rejects `""`, so we model the server returning a
        // single-field schema instead — this confirms the response is what
        // dictates the returned value.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listSchemaEnvelope("Title:text"))
        let service = ListsService(api: api)

        // When
        let result = try await service.updateSchema(of: "books", schema: ListSchema.empty)

        // Then
        XCTAssertEqual(result.fields.map(\.name), ["Title"])
    }

    // MARK: - refresh

    func test_givenGitHubBackedList_whenRefreshing_thenReturnsFreshList() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listObject(id: "gh-list"))
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
        await api.enqueue(json: Fixtures.listRowObject(id: "row-7"))
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

    // MARK: - row CRUD

    func test_givenRowData_whenCreatingRow_thenPostsAndMapsResponse() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listRowObject(id: "row-new"))
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
        await api.enqueue(json: Fixtures.listRowObject(id: "row-empty"))
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

    func test_givenUpdate_whenUpdatingRow_thenPatchesAndMapsResponse() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listRowObject(id: "row-7"))
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
        XCTAssertEqual(recorded.first?.method, "PATCH")
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
        await api.enqueue(json: Fixtures.watchersArray([
            (userId: "u-1", role: "owner"),
            (userId: "u-2", role: "editor"),
            (userId: "u-3", role: "viewer")
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
        await api.enqueue(json: "[]")
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
        await api.enqueue(json: Fixtures.watchersArray([(userId: "u-1", role: "admin")]))
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
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watcherObject(userId: "u-9", role: "editor"))
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

    func test_givenSetWatcherAPIFailure_whenSettingWatcher_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "only owners can share"))
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
            XCTAssertEqual(error, .forbidden(serverMessage: "only owners can share"))
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
