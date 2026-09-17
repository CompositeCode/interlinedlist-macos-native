import XCTest
@testable import InterlinedKit

/// BDD coverage for the five saved-list-view routes (work-consolidation.md G40
/// / issue #81).
///
/// **Every JSON literal below is a payload the live API actually produced on
/// 2026-09-15**, not a shape derived from the OpenAPI document. That
/// distinction is the point of this suite: the spec is wrong about this
/// resource in two separate ways, and issue #81 asks specifically for a
/// contract test that fails on a renamed key instead of degrading to `nil`.
///
///  • `createdAt` / `updatedAt` are REQUIRED in the spec and absent from every
///    live response — `test_givenLiveViewRowWithoutTimestamps_…` is the
///    regression guard.
///  • The spec's `config.filters` example was sent verbatim to the live API and
///    came back `[]` — `test_givenSpecExampleFilter_…` records that, so nobody
///    "fixes" the model back toward the document.
final class ListViewsEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_abc")
    ) -> (APIClient, StubHTTPDataTransport) {
        // One stub backs both transports so the decision-0001 401 safety net
        // (which retries a Bearer 401 once over the session) reads from a
        // single queue.
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: transport,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    /// The exact live create/GET row, verbatim. Kept in one place so every test
    /// below asserts against the same captured bytes.
    private static let liveViewRow = """
    {"id":"v-1","listId":"33de2874-55cc-4b6e-be02-f6868a0cf0a9","userId":"c65",
     "name":"Reading","scope":"personal",
     "config":{"mode":"records","density":"comfortable","filters":[]},
     "isDefault":false,"position":0}
    """

    // MARK: - Builder shape

    func test_givenSavedViewBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        // All five are Bearer and unpaged — the collection route returns a bare
        // `{views:[…]}` with no pagination envelope, so `paginationKey` must
        // stay nil or `PaginatedDecoder` would be pointed at a key that is not
        // there.
        let list = Lists.views(listId: "L1")
        XCTAssertEqual(list.method, .get)
        XCTAssertEqual(list.path, "/api/lists/L1/views")
        XCTAssertEqual(list.auth, .bearer)
        XCTAssertNil(list.paginationKey)

        let create = Lists.createView(listId: "L1", CreateListViewRequest(name: "Reading", scope: "personal"))
        XCTAssertEqual(create.method, .post)
        XCTAssertEqual(create.path, "/api/lists/L1/views")
        XCTAssertEqual(create.auth, .bearer)
        XCTAssertNotNil(create.body)

        // Fork shares the verb with create and differs only by depth — assert
        // the path so the two can never be transposed.
        let fork = Lists.forkView(listId: "L1", viewId: "v-1", ForkListViewRequest(name: "Mine"))
        XCTAssertEqual(fork.method, .post)
        XCTAssertEqual(fork.path, "/api/lists/L1/views/v-1")
        XCTAssertEqual(fork.auth, .bearer)

        let update = Lists.updateView(listId: "L1", viewId: "v-1", UpdateListViewRequest(name: "Renamed"))
        XCTAssertEqual(update.method, .put)
        XCTAssertEqual(update.path, "/api/lists/L1/views/v-1")

        let remove = Lists.deleteView(listId: "L1", viewId: "v-1")
        XCTAssertEqual(remove.method, .delete)
        XCTAssertEqual(remove.path, "/api/lists/L1/views/v-1")
        XCTAssertEqual(remove.auth, .bearer)
    }

    // MARK: - GET /views

    func test_givenLiveViewRowWithoutTimestamps_whenListingViews_thenDecodesEveryField() async throws {
        // Given — two rows in the live eight-key shape: one shared, one
        // personal-and-default. Neither carries createdAt/updatedAt, which the
        // spec marks required; a schema-faithful decoder throws here.
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"views":[
          {"id":"v-1","listId":"L1","userId":"c65","name":"Team board","scope":"shared",
           "config":{"mode":"records","density":"compact","filters":[]},
           "isDefault":false,"position":0},
          {"id":"v-2","listId":"L1","userId":"c65","name":"Mine","scope":"personal",
           "config":{"mode":"records","density":"comfortable","filters":[]},
           "isDefault":true,"position":0}
        ]}
        """, status: 200))

        // When
        let response = try await client.send(Lists.views(listId: "L1"))

        // Then
        XCTAssertEqual(response.views.map(\.id), ["v-1", "v-2"])
        XCTAssertEqual(response.views.map(\.scope), ["shared", "personal"])
        XCTAssertEqual(response.views.map(\.isDefault), [false, true])
        XCTAssertEqual(response.views.map(\.config.density), ["compact", "comfortable"])
        XCTAssertEqual(response.views.first?.userId, "c65")
        // `position` is per-scope-bucket, so both rows legitimately read 0.
        XCTAssertEqual(response.views.map(\.position), [0, 0])
        XCTAssertNil(response.views.first?.createdAt)
        XCTAssertNil(response.views.first?.updatedAt)
    }

    func test_givenRenamedKey_whenListingViews_thenFailsTheDecodeRatherThanDegrading() async throws {
        // Invalid input: `isDefault` arrives under a renamed key. Issue #81's
        // acceptance criterion is that this FAILS rather than quietly reading
        // as `nil`/`false` — the G21 and G25 defect mode. `isDefault` is the
        // sharpest case: silently false means the user's chosen default view
        // stops opening and nothing anywhere reports an error.
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"views":[{"id":"v-1","listId":"L1","userId":"c65","name":"Reading","scope":"personal",
          "config":{"mode":"records","density":"comfortable","filters":[]},
          "default":false,"position":0}]}
        """, status: 200))

        do {
            _ = try await client.send(Lists.views(listId: "L1"))
            XCTFail("Expected a decode failure on the renamed isDefault key")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected APIError.decoding, got \(error)")
            }
        }
    }

    func test_givenListWithNoSavedViews_whenListingViews_thenDecodesEmptyCollection() async throws {
        // Boundary — the literal live body re-confirmed by GET on 2026-09-16.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"views":[]}"#, status: 200))

        let response = try await client.send(Lists.views(listId: "L1"))

        XCTAssertTrue(response.views.isEmpty)
    }

    func test_givenUnauthorizedCaller_whenListingViews_thenSurfacesUnauthorized() async throws {
        // Upstream failure. Two enqueues: the 401 safety net retries once over
        // the session transport before surfacing the status.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))
        await transport.enqueue(.json(#"{"error":"Unauthorized"}"#, status: 401))

        do {
            _ = try await client.send(Lists.views(listId: "L1"))
            XCTFail("Expected APIError.unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 401)
        }
    }

    // MARK: - POST /views (create)

    func test_givenNamedPersonalView_whenCreating_thenSendsConfigAsObjectAndDecodesEnvelope() async throws {
        // The single most important assertion in this file: `config` goes out
        // as a JSON **object**. The OpenAPI request body declares it
        // `{"type":"string"}` — issue #81 was filed on that reading — and a
        // live POST with an object returned 201.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"view":\#(Self.liveViewRow)}"#, status: 201))

        let response = try await client.send(
            Lists.createView(
                listId: "L1",
                CreateListViewRequest(
                    name: "Reading",
                    scope: "personal",
                    config: ListViewConfigDTO(mode: "records", density: "comfortable"),
                    isDefault: false
                )
            )
        )

        XCTAssertEqual(response.view.id, "v-1")
        XCTAssertEqual(response.view.scope, "personal")
        XCTAssertEqual(response.view.config.mode, "records")

        let sent = await transport.received
        XCTAssertEqual(sent.last?.httpMethod, "POST")
        XCTAssertEqual(sent.last?.url?.path, "/api/lists/L1/views")
        let body = try XCTUnwrap(sent.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Reading")
        XCTAssertEqual(json["scope"] as? String, "personal")
        XCTAssertTrue(json["config"] is [String: Any], "config must be sent as an object, not a string")
        let config = try XCTUnwrap(json["config"] as? [String: Any])
        XCTAssertEqual(config["mode"] as? String, "records")
        XCTAssertEqual(config["density"] as? String, "comfortable")
    }

    func test_givenSpecExampleFilter_whenCreating_thenRoundTripsWhateverTheServerStored() async throws {
        // The spec's own response example shows this filter surviving. It does
        // not: the live API answered `"filters": []` to exactly this body. The
        // client must therefore send the filter opaquely and believe the
        // response, never its own optimistic copy.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"view":\#(Self.liveViewRow)}"#, status: 201))

        _ = try await client.send(
            Lists.createView(
                listId: "L1",
                CreateListViewRequest(
                    name: "Unread",
                    scope: "personal",
                    config: ListViewConfigDTO(
                        mode: "records",
                        density: "comfortable",
                        filters: [.object(["key": .string("read"), "op": .string("eq"), "value": .bool(false)])]
                    )
                )
            )
        )

        let sent = await transport.received
        let body = try XCTUnwrap(sent.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let config = try XCTUnwrap(json["config"] as? [String: Any])
        let filters = try XCTUnwrap(config["filters"] as? [[String: Any]])
        XCTAssertEqual(filters.first?["key"] as? String, "read")
        XCTAssertEqual(filters.first?["op"] as? String, "eq")
        XCTAssertEqual(filters.first?["value"] as? Bool, false)
    }

    func test_givenOmittedOptionalFields_whenCreating_thenSkipsThemInTheBody() async throws {
        // Boundary: omitting `config` is legal and makes the server apply its
        // default. Sending `"config": null` is not the same thing, so assert
        // the keys are genuinely absent.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"view":\#(Self.liveViewRow)}"#, status: 201))

        _ = try await client.send(
            Lists.createView(listId: "L1", CreateListViewRequest(name: "Plain", scope: "shared"))
        )

        let sent = await transport.received
        let body = try XCTUnwrap(sent.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["config"])
        XCTAssertNil(json["isDefault"])
        XCTAssertEqual(json.keys.sorted(), ["name", "scope"])
    }

    func test_givenIllegalScope_whenCreating_thenSurfacesTheServersBadRequest() async throws {
        // Upstream failure, and the asymmetry worth encoding: `scope` is the
        // one field the server validates. Verbatim live body.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(
            #"{"error":"scope must be \"personal\" or \"shared\"","code":"bad_request"}"#,
            status: 400
        ))

        do {
            _ = try await client.send(
                Lists.createView(listId: "L1", CreateListViewRequest(name: "X", scope: "bogus_scope"))
            )
            XCTFail("Expected APIError.badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 400)
            guard case .badRequest(let message) = error else {
                return XCTFail("Expected APIError.badRequest, got \(error)")
            }
            XCTAssertEqual(message, #"scope must be "personal" or "shared""#)
        }
    }

    // MARK: - POST /views/{id} (fork)

    func test_givenSharedView_whenForking_thenPostsToTheViewPathAndDecodesTheCopy() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"view":{"id":"v-9","listId":"L1","userId":"c65","name":"My copy","scope":"personal",
          "config":{"mode":"records","density":"compact","filters":[]},
          "isDefault":false,"position":1}}
        """, status: 201))

        let response = try await client.send(
            Lists.forkView(listId: "L1", viewId: "v-1", ForkListViewRequest(name: "My copy"))
        )

        // A fork always lands in the caller's personal bucket — that is the
        // whole point of the "escape hatch".
        XCTAssertEqual(response.view.id, "v-9")
        XCTAssertEqual(response.view.scope, "personal")
        XCTAssertEqual(response.view.config.density, "compact")
        let sent = await transport.received
        XCTAssertEqual(sent.last?.httpMethod, "POST")
        XCTAssertEqual(sent.last?.url?.path, "/api/lists/L1/views/v-1")
    }

    func test_givenNoName_whenForking_thenSendsAnEmptyBodyAndLetsTheServerName() async throws {
        // Boundary: the name is optional on fork.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"view":\#(Self.liveViewRow)}"#, status: 201))

        _ = try await client.send(Lists.forkView(listId: "L1", viewId: "v-1", ForkListViewRequest()))

        let sent = await transport.received
        let body = try XCTUnwrap(sent.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertTrue(json.isEmpty)
    }

    func test_givenMissingSourceView_whenForking_thenSurfacesNotFound() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"View not found","code":"not_found"}"#, status: 404))

        do {
            _ = try await client.send(Lists.forkView(listId: "L1", viewId: "nope", ForkListViewRequest()))
            XCTFail("Expected APIError.notFound")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 404)
        }
    }

    // MARK: - PUT /views/{id}

    func test_givenFullConfig_whenUpdating_thenSendsEveryConfigKeyBecausePutReplaces() async throws {
        // PUT replaces the config object whole — a live PUT that omitted
        // `density` reset it from "compact" to "comfortable". So the request
        // must carry every key the caller wants to keep.
        let (client, transport) = makeClient()
        await transport.enqueue(.json("""
        {"view":{"id":"v-1","listId":"L1","userId":"c65","name":"Reading","scope":"personal",
          "config":{"mode":"records","density":"compact","filters":[]},
          "isDefault":true,"position":0}}
        """, status: 200))

        let response = try await client.send(
            Lists.updateView(
                listId: "L1",
                viewId: "v-1",
                UpdateListViewRequest(
                    name: "Reading",
                    config: ListViewConfigDTO(mode: "records", density: "compact"),
                    isDefault: true
                )
            )
        )

        XCTAssertEqual(response.view.config.density, "compact")
        XCTAssertTrue(response.view.isDefault)
        let sent = await transport.received
        XCTAssertEqual(sent.last?.httpMethod, "PUT")
        let body = try XCTUnwrap(sent.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let config = try XCTUnwrap(json["config"] as? [String: Any])
        XCTAssertEqual(config["mode"] as? String, "records")
        XCTAssertEqual(config["density"] as? String, "compact")
        XCTAssertNotNil(config["filters"])
    }

    func test_givenRenameOnly_whenUpdating_thenOmitsConfigEntirely() async throws {
        // Boundary: a pure rename must NOT send a partial config — an
        // incomplete object would replace the stored one and silently reset
        // whatever it left out.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"view":\#(Self.liveViewRow)}"#, status: 200))

        _ = try await client.send(
            Lists.updateView(listId: "L1", viewId: "v-1", UpdateListViewRequest(name: "Renamed"))
        )

        let sent = await transport.received
        let body = try XCTUnwrap(sent.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json.keys.sorted(), ["name"])
    }

    func test_givenForbiddenUpdate_whenUpdatingSomeoneElsesView_thenSurfacesForbidden() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Forbidden"}"#, status: 403))

        do {
            _ = try await client.send(
                Lists.updateView(listId: "L1", viewId: "v-1", UpdateListViewRequest(name: "X"))
            )
            XCTFail("Expected APIError.forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 403)
        }
    }

    // MARK: - DELETE /views/{id}

    func test_givenExistingView_whenDeleting_thenSendsDeleteAndIgnoresTheMessageBody() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"message":"View deleted"}"#, status: 200))

        try await client.sendVoid(Lists.deleteView(listId: "L1", viewId: "v-1"))

        let sent = await transport.received
        XCTAssertEqual(sent.last?.httpMethod, "DELETE")
        XCTAssertEqual(sent.last?.url?.path, "/api/lists/L1/views/v-1")
    }

    func test_givenMissingView_whenDeleting_thenSurfacesNotFound() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"View not found","code":"not_found"}"#, status: 404))

        do {
            try await client.sendVoid(Lists.deleteView(listId: "L1", viewId: "nope"))
            XCTFail("Expected APIError.notFound")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 404)
        }
    }
}
