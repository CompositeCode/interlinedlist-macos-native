import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD coverage for the saved-list-views domain surface
/// (work-consolidation.md G40 / issue #81):
/// `ListsService.savedViews` / `createSavedView` / `updateSavedView` /
/// `deleteSavedView` / `forkSavedView`, plus the `SavedListView*` mappers.
///
/// Envelopes are the live payloads captured on 2026-09-15; the `{"views":[]}`
/// empty case was re-read on 2026-09-16. Quartet (happy / invalid input /
/// upstream failure / boundary) per method.
final class SavedListViewsServiceTests: XCTestCase {

    /// The live eight-key row. No `createdAt` / `updatedAt` — the spec marks
    /// both required and the API sends neither.
    private func viewRow(
        id: String = "v-1",
        name: String = "Reading",
        scope: String = "personal",
        mode: String = "records",
        density: String = "comfortable",
        filters: String = "[]",
        isDefault: Bool = false,
        position: Int = 0
    ) -> String {
        """
        {"id":"\(id)","listId":"L1","userId":"c65","name":"\(name)","scope":"\(scope)",
         "config":{"mode":"\(mode)","density":"\(density)","filters":\(filters)},
         "isDefault":\(isDefault),"position":\(position)}
        """
    }

    // MARK: - savedViews

    func test_givenSharedAndPersonalViews_whenLoading_thenMapsScopeConfigAndDefault() async throws {
        // Given — the collection route mixes both scopes in one array, which is
        // exactly why the UI has to render the discriminator.
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"views":[
          \(viewRow(id: "v-1", name: "Team board", scope: "shared", density: "compact")),
          \(viewRow(id: "v-2", name: "Mine", scope: "personal", isDefault: true, position: 1))
        ]}
        """)
        let service = ListsService(api: api)

        // When
        let views = try await service.savedViews(of: "L1")

        // Then
        XCTAssertEqual(views.map(\.id), ["v-1", "v-2"])
        XCTAssertEqual(views.map(\.scope), [.shared, .personal])
        XCTAssertEqual(views.first?.config.density, .compact)
        XCTAssertEqual(views.first?.config.mode, .records)
        XCTAssertTrue(views.first?.isShared ?? false)
        XCTAssertEqual(views.last?.isDefault, true)
        XCTAssertEqual(views.first?.ownerID, "c65")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "GET")
        XCTAssertEqual(recorded.first?.path, "/api/lists/L1/views")
    }

    func test_givenUnknownModeAndDensity_whenLoading_thenCarriesTheTokensRatherThanRewritingThem() async throws {
        // Invalid input from upstream. The server *silently defaults* unknown
        // config values instead of erroring, so a token this build does not know
        // is a real state: collapsing it to `.records` / `.comfortable` would
        // overwrite the user's stored choice on the next save.
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"views":[\(viewRow(mode: "kanban", density: "spacious"))]}
        """)
        let service = ListsService(api: api)

        let views = try await service.savedViews(of: "L1")

        XCTAssertEqual(views.first?.config.mode, .unknown("kanban"))
        XCTAssertEqual(views.first?.config.density, .unknown("spacious"))
        // …and the tokens survive the round-trip back to the wire.
        XCTAssertEqual(views.first?.config.wireValue.mode, "kanban")
        XCTAssertEqual(views.first?.config.wireValue.density, "spacious")
    }

    func test_givenUnrecognisedScope_whenLoading_thenTreatsItAsPersonal() async throws {
        // Invalid input from upstream. Of the two possible mistakes, calling a
        // shared view personal is the safe one: the opposite would tell the user
        // their private filters are visible to collaborators.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"views":[\#(viewRow(scope: "organisation"))]}"#)
        let service = ListsService(api: api)

        let views = try await service.savedViews(of: "L1")

        XCTAssertEqual(views.first?.scope, .personal)
        XCTAssertFalse(views.first?.isShared ?? true)
    }

    func test_givenOpaqueFilters_whenLoading_thenRoundTripsThemUntouched() async throws {
        // The filters element grammar is UNCONFIRMED — the recon list has an
        // empty schema, so every probe filter was dropped and a grammar failure
        // could not be told from a column-not-found. The client therefore has
        // to preserve whatever the web wrote rather than parse it.
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"views":[\(viewRow(filters: #"[{"key":"read","op":"eq","value":false}]"#))]}
        """)
        let service = ListsService(api: api)

        let views = try await service.savedViews(of: "L1")

        let filters = try XCTUnwrap(views.first?.config.filters)
        XCTAssertEqual(filters.count, 1)
        guard case .object(let first) = filters[0] else {
            return XCTFail("Expected the filter to survive as an opaque object")
        }
        XCTAssertEqual(first["key"], .string("read"))
        XCTAssertEqual(first["op"], .string("eq"))
        XCTAssertEqual(first["value"], .bool(false))
        // Back out to the wire unchanged.
        let wire = try XCTUnwrap(views.first?.config.wireValue.filters)
        XCTAssertEqual(wire, [.object(["key": .string("read"), "op": .string("eq"), "value": .bool(false)])])
    }

    func test_givenListWithNoViews_whenLoading_thenReturnsEmpty() async throws {
        // Boundary — the literal live body.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"views":[]}"#)
        let service = ListsService(api: api)

        let views = try await service.savedViews(of: "L1")

        XCTAssertTrue(views.isEmpty)
    }

    func test_givenUpstreamFailure_whenLoading_thenPropagatesTheAPIError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "Unauthorized"))
        let service = ListsService(api: api)

        do {
            _ = try await service.savedViews(of: "L1")
            XCTFail("Expected APIError.unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "Unauthorized"))
        }
    }

    // MARK: - createSavedView

    func test_givenNamedPersonalView_whenCreating_thenSendsScopeTokenAndConfigObject() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"view":\#(viewRow(name: "Reading"))}"#)
        let service = ListsService(api: api)

        let created = try await service.createSavedView(
            listId: "L1",
            name: "Reading",
            scope: .personal,
            config: SavedListViewConfig(mode: .records, density: .comfortable),
            isDefault: false
        )

        XCTAssertEqual(created.id, "v-1")
        XCTAssertEqual(created.scope, .personal)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/L1/views")
        let body = try await lastSentJSON(api)
        XCTAssertEqual(body["name"] as? String, "Reading")
        XCTAssertEqual(body["scope"] as? String, "personal")
        // `config` must be an object — the OpenAPI request body declares it a
        // string, which is what issue #81 was filed on, and a string is
        // rejected.
        let config = try XCTUnwrap(body["config"] as? [String: Any])
        XCTAssertEqual(config["mode"] as? String, "records")
        XCTAssertEqual(config["density"] as? String, "comfortable")
    }

    func test_givenBlankName_whenCreating_thenThrowsWithoutCallingTheAPI() async throws {
        // Invalid input. The route happily accepts "" — nothing server-side
        // stops an unlabelled row landing in the picker — so the guard has to
        // be here, and it has to fire before the round-trip.
        let api = StubAPIClient()
        let service = ListsService(api: api)

        do {
            _ = try await service.createSavedView(
                listId: "L1",
                name: "   ",
                scope: .personal,
                config: .serverDefault,
                isDefault: false
            )
            XCTFail("Expected ListsError.invalidViewName")
        } catch let error as ListsError {
            XCTAssertEqual(error, .invalidViewName)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "A blank name must not spend a round-trip")
    }

    func test_givenSurroundingWhitespace_whenCreating_thenSendsTheTrimmedName() async throws {
        // Boundary: a name that is only *nearly* blank is legal, trimmed.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"view":\#(viewRow(name: "Reading"))}"#)
        let service = ListsService(api: api)

        _ = try await service.createSavedView(
            listId: "L1",
            name: "  Reading  ",
            scope: .shared,
            config: .serverDefault,
            isDefault: false
        )

        let body = try await lastSentJSON(api)
        XCTAssertEqual(body["name"] as? String, "Reading")
        XCTAssertEqual(body["scope"] as? String, "shared")
    }

    func test_givenServerRejectingScope_whenCreating_thenPropagatesTheBadRequest() async throws {
        // Upstream failure, and the asymmetry the client is built around:
        // `scope` hard-fails where every config value defaults silently.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: #"scope must be "personal" or "shared""#))
        let service = ListsService(api: api)

        do {
            _ = try await service.createSavedView(
                listId: "L1",
                name: "Reading",
                scope: .personal,
                config: .serverDefault,
                isDefault: false
            )
            XCTFail("Expected APIError.badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: #"scope must be "personal" or "shared""#))
        }
    }

    func test_givenServerNormalisingTheConfig_whenCreating_thenReturnsTheStoredArrangement() async throws {
        // The request and the stored view routinely disagree — an unknown mode
        // comes back as `records`. The caller must get the server's row, never
        // its own optimistic copy.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"view":\#(viewRow(mode: "records"))}"#)
        let service = ListsService(api: api)

        let created = try await service.createSavedView(
            listId: "L1",
            name: "Board",
            scope: .personal,
            config: SavedListViewConfig(mode: .unknown("kanban"), density: .compact),
            isDefault: false
        )

        XCTAssertEqual(created.config.mode, .records)
        XCTAssertEqual(created.config.density, .comfortable)
    }

    // MARK: - updateSavedView

    func test_givenFullConfig_whenUpdating_thenSendsEveryConfigKey() async throws {
        // PUT replaces the config whole: a live PUT that omitted `density`
        // reset it from "compact" to "comfortable". `SavedListViewConfig` is
        // non-partial by construction so a half-config cannot be built.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"view":\#(viewRow(density: "compact", isDefault: true))}"#)
        let service = ListsService(api: api)

        let updated = try await service.updateSavedView(
            listId: "L1",
            viewId: "v-1",
            name: "Reading",
            config: SavedListViewConfig(mode: .records, density: .compact),
            isDefault: true
        )

        XCTAssertEqual(updated.config.density, .compact)
        XCTAssertTrue(updated.isDefault)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/lists/L1/views/v-1")
        let body = try await lastSentJSON(api)
        let config = try XCTUnwrap(body["config"] as? [String: Any])
        XCTAssertEqual(config["mode"] as? String, "records")
        XCTAssertEqual(config["density"] as? String, "compact")
        XCTAssertNotNil(config["filters"])
    }

    func test_givenBlankRename_whenUpdating_thenThrowsWithoutCallingTheAPI() async throws {
        // Invalid input.
        let api = StubAPIClient()
        let service = ListsService(api: api)

        do {
            _ = try await service.updateSavedView(
                listId: "L1",
                viewId: "v-1",
                name: "",
                config: nil,
                isDefault: nil
            )
            XCTFail("Expected ListsError.invalidViewName")
        } catch let error as ListsError {
            XCTAssertEqual(error, .invalidViewName)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenOnlyTheDefaultFlag_whenUpdating_thenOmitsNameAndConfig() async throws {
        // Boundary: marking a view as the default must not touch its
        // arrangement. An omitted `config` leaves the stored one alone; a
        // partial one would silently reset whatever it left out.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"view":\#(viewRow(isDefault: true))}"#)
        let service = ListsService(api: api)

        _ = try await service.updateSavedView(
            listId: "L1",
            viewId: "v-1",
            name: nil,
            config: nil,
            isDefault: true
        )

        let body = try await lastSentJSON(api)
        XCTAssertEqual(body.keys.sorted(), ["isDefault"])
        XCTAssertEqual(body["isDefault"] as? Bool, true)
    }

    func test_givenUpstreamFailure_whenUpdating_thenPropagatesTheAPIError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "Forbidden"))
        let service = ListsService(api: api)

        do {
            _ = try await service.updateSavedView(
                listId: "L1",
                viewId: "v-1",
                name: "Renamed",
                config: nil,
                isDefault: nil
            )
            XCTFail("Expected APIError.forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "Forbidden"))
        }
    }

    // MARK: - deleteSavedView

    func test_givenExistingView_whenDeleting_thenSendsDelete() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"message":"View deleted"}"#)
        let service = ListsService(api: api)

        try await service.deleteSavedView(listId: "L1", viewId: "v-1")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/lists/L1/views/v-1")
    }

    func test_givenMissingView_whenDeleting_thenPropagatesNotFound() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "View not found"))
        let service = ListsService(api: api)

        do {
            try await service.deleteSavedView(listId: "L1", viewId: "nope")
            XCTFail("Expected APIError.notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "View not found"))
        }
    }

    // MARK: - forkSavedView

    func test_givenSharedView_whenForking_thenReturnsAPersonalCopy() async throws {
        // The escape hatch: take the owner's arrangement and make it yours
        // rather than being stuck with it.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"view":\#(viewRow(id: "v-9", name: "My copy", scope: "personal", density: "compact", position: 1))}"#)
        let service = ListsService(api: api)

        let forked = try await service.forkSavedView(listId: "L1", viewId: "v-1", name: "My copy")

        XCTAssertEqual(forked.id, "v-9")
        XCTAssertEqual(forked.scope, .personal)
        XCTAssertEqual(forked.config.density, .compact)
        let recorded = await api.recorded
        // Same verb as create — only the deeper path distinguishes them.
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/L1/views/v-1")
        let body = try await lastSentJSON(api)
        XCTAssertEqual(body["name"] as? String, "My copy")
    }

    func test_givenBlankForkName_whenForking_thenThrowsWithoutCallingTheAPI() async throws {
        // Invalid input: a *supplied* blank name is a mistake. A nil name is
        // not — see the boundary case below.
        let api = StubAPIClient()
        let service = ListsService(api: api)

        do {
            _ = try await service.forkSavedView(listId: "L1", viewId: "v-1", name: " ")
            XCTFail("Expected ListsError.invalidViewName")
        } catch let error as ListsError {
            XCTAssertEqual(error, .invalidViewName)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenNoForkName_whenForking_thenSendsAnEmptyBodyAndLetsTheServerName() async throws {
        // Boundary: the name is optional on fork.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"view":\#(viewRow(id: "v-9"))}"#)
        let service = ListsService(api: api)

        let forked = try await service.forkSavedView(listId: "L1", viewId: "v-1", name: nil)

        XCTAssertEqual(forked.id, "v-9")
        let body = try await lastSentJSON(api)
        XCTAssertTrue(body.isEmpty)
    }

    func test_givenMissingSourceView_whenForking_thenPropagatesNotFound() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "View not found"))
        let service = ListsService(api: api)

        do {
            _ = try await service.forkSavedView(listId: "L1", viewId: "nope", name: "Copy")
            XCTFail("Expected APIError.notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "View not found"))
        }
    }

    // MARK: - Free on every tier

    func test_givenFreeAccount_whenUsingSavedViews_thenNoSubscriberGateApplies() async throws {
        // The five routes are `x-subscription-tier: free` and were all reached
        // live on a free account. Arranging a list you can already read is not
        // creating one (GitHub #40 matrix), so a free entitlement must not
        // short-circuit any of them before the HTTP call.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"view":\#(viewRow())}"#)
        let service = ListsService(api: api, entitlements: EntitlementsService(customerStatus: .free))

        let created = try await service.createSavedView(
            listId: "L1",
            name: "Reading",
            scope: .personal,
            config: .serverDefault,
            isDefault: false
        )

        XCTAssertEqual(created.id, "v-1")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }
}
