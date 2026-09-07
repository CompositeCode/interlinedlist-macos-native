import XCTest
@testable import InterlinedKit

/// BDD tests for the "Create from…" / materialize endpoint (work-consolidation.md G16).
///
/// The encoded source refs below match the shapes the web client builds and that
/// the live route accepted on 2026-09-05 (well-formed ref + unknown id → 404,
/// which proves the shape parsed and that nothing was created).
final class MaterializeEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport()
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_abc"),
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        return (APIClient(baseURL: baseURL, transport: transport, authTransport: auth), transport)
    }

    private func sentJSON(_ transport: StubHTTPDataTransport) async throws -> [String: Any] {
        let received = await transport.received
        let body = try XCTUnwrap(received.first?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - Builder shape

    func test_givenMaterializeBuilder_whenConstructed_thenUsesExpectedMethodPathAuth() {
        let request = Materialize.create(MaterializeRequest(
            target: .doc, source: .messages(ids: ["m1"]),
            docConfig: MaterializeDocConfig(title: "Doc")
        ))
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/materialize")
        XCTAssertEqual(request.auth, .bearer)
    }

    func test_givenEnums_whenSerialized_thenUseTheLiveWireNames() {
        XCTAssertEqual(MaterializeTarget.allCases.map(\.rawValue), ["list", "doc", "both"])
        XCTAssertEqual(MaterializeListStyle.allCases.map(\.rawValue), ["bulleted", "numbered"])
        XCTAssertEqual(MaterializeRowDataStyle.allCases.map(\.rawValue), ["table", "inline", "paragraph"])
        XCTAssertEqual(MaterializeFieldType.allCases.map(\.rawValue),
                       ["text", "textarea", "number", "date", "datetime", "boolean",
                        "select", "multiselect", "email", "url", "tel", "priority"])
    }

    // MARK: - Happy path

    func test_givenEverySourceKind_whenEncoded_thenMatchesTheWireShape() async throws {
        let cases: [(MaterializeSource, [String: Any])] = [
            (.messages(ids: ["m1", "m2"]), ["kind": "messages", "messageIds": ["m1", "m2"]]),
            (.lists(ids: ["l1"]), ["kind": "lists", "listIds": ["l1"]]),
            (.rows(listId: "l1", rowIds: ["r1"]), ["kind": "rows", "listId": "l1", "rowIds": ["r1"]]),
            (.document(id: "d1"), ["kind": "document", "documentId": "d1"]),
            (.documentElements(documentId: "d1", markdown: "# hi"),
             ["kind": "docElements", "documentId": "d1", "markdown": "# hi"])
        ]

        for (source, expected) in cases {
            let (client, transport) = makeClient()
            await transport.enqueue(.json(#"{"document":{"id":"d-new","title":"Doc"}}"#, status: 201))

            _ = try await client.send(Materialize.create(MaterializeRequest(
                target: .doc, source: source, docConfig: MaterializeDocConfig(title: "Doc")
            )))

            let json = try await sentJSON(transport)
            let encoded = try XCTUnwrap(json["source"] as? [String: Any])
            XCTAssertEqual(encoded["kind"] as? String, expected["kind"] as? String)
            for key in expected.keys where key != "kind" {
                if let strings = expected[key] as? [String] {
                    XCTAssertEqual(encoded[key] as? [String], strings, "\(key)")
                } else {
                    XCTAssertEqual(encoded[key] as? String, expected[key] as? String, "\(key)")
                }
            }
        }
    }

    func test_givenBothTarget_whenSent_thenEncodesListAndDocConfigs() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"list":{"id":"l-new","title":"From messages"},"document":{"id":"d-new","title":"From messages"}}"#, status: 201))

        let response = try await client.send(Materialize.create(MaterializeRequest(
            target: .both,
            source: .messages(ids: ["m1"]),
            listConfig: MaterializeListConfig(
                title: "From messages", description: "desc", isPublic: true,
                fields: [MaterializeField(propertyKey: "content", propertyName: "Content", propertyType: .textarea)],
                includeData: true
            ),
            docConfig: MaterializeDocConfig(
                title: "From messages", relativePath: "notes/", isPublic: false,
                listStyle: .numbered, rowDataStyle: .inline
            )
        )))

        let json = try await sentJSON(transport)
        XCTAssertEqual(json["target"] as? String, "both")
        let list = try XCTUnwrap(json["listConfig"] as? [String: Any])
        XCTAssertEqual(list["title"] as? String, "From messages")
        XCTAssertEqual(list["isPublic"] as? Bool, true)
        XCTAssertEqual(list["includeData"] as? Bool, true)
        let field = try XCTUnwrap((list["fields"] as? [[String: Any]])?.first)
        XCTAssertEqual(field["propertyKey"] as? String, "content")
        XCTAssertEqual(field["propertyName"] as? String, "Content")
        XCTAssertEqual(field["propertyType"] as? String, "textarea")
        XCTAssertEqual(field["sourceKey"] as? String, "content", "sourceKey defaults to propertyKey")
        let doc = try XCTUnwrap(json["docConfig"] as? [String: Any])
        XCTAssertEqual(doc["listStyle"] as? String, "numbered")
        XCTAssertEqual(doc["rowDataStyle"] as? String, "inline")
        XCTAssertEqual(doc["relativePath"] as? String, "notes/")
        XCTAssertEqual(response.list?.id, "l-new")
        XCTAssertEqual(response.list?.title, "From messages")
        XCTAssertEqual(response.listId, "l-new", "the nested id is surfaced flat for callers")
        XCTAssertEqual(response.documentId, "d-new")
    }

    func test_givenDocOnlyTarget_whenSent_thenListConfigIsOmitted() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"documentId":"d-new"}"#, status: 201))

        _ = try await client.send(Materialize.create(MaterializeRequest(
            target: .doc, source: .document(id: "d1"), docConfig: MaterializeDocConfig(title: "Copy")
        )))

        let json = try await sentJSON(transport)
        XCTAssertNil(json["listConfig"], "An absent listConfig must not serialize as null")
    }

    /// Pinned to the payload captured from the web app on 2026-09-05. If this
    /// drifts, Create-from silently stops matching the only shape the server
    /// accepts — the route's error message will not tell you why.
    func test_givenTheDefaultMessageColumns_whenEncoded_thenMatchesTheWebAppsPayloadExactly() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"listId":"l-new"}"#, status: 201))

        _ = try await client.send(Materialize.create(MaterializeRequest(
            target: .list,
            source: .messages(ids: ["ba1e50cc-4aaf-48c4-b138-6945f6a5a876"]),
            listConfig: MaterializeListConfig(
                title: "Message by @adron",
                isPublic: false,
                fields: [
                    MaterializeField(propertyKey: "content", propertyName: "Content", propertyType: .textarea),
                    MaterializeField(propertyKey: "author", propertyName: "Author", propertyType: .text),
                    MaterializeField(propertyKey: "posted", propertyName: "Posted", propertyType: .text),
                    MaterializeField(propertyKey: "links", propertyName: "Links", propertyType: .textarea),
                    MaterializeField(propertyKey: "tags", propertyName: "Tags", propertyType: .text)
                ],
                includeData: true
            )
        )))

        let json = try await sentJSON(transport)
        let list = try XCTUnwrap(json["listConfig"] as? [String: Any])
        let fields = try XCTUnwrap(list["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.count, 5)
        XCTAssertEqual(fields.map { $0["propertyKey"] as? String },
                       ["content", "author", "posted", "links", "tags"])
        XCTAssertEqual(fields.map { $0["propertyName"] as? String },
                       ["Content", "Author", "Posted", "Links", "Tags"])
        XCTAssertEqual(fields.map { $0["propertyType"] as? String },
                       ["textarea", "text", "text", "textarea", "text"])
        XCTAssertEqual(fields.map { $0["sourceKey"] as? String },
                       ["content", "author", "posted", "links", "tags"])
        XCTAssertEqual(list["includeData"] as? Bool, true)
        XCTAssertEqual(list["isPublic"] as? Bool, false)
    }

    // MARK: - Invalid input

    func test_givenMissingListTitle_whenSent_thenSurfacesTheServerRejection() async throws {
        let (client, transport) = makeClient()
        // The live 400 for a list target with no title, verbatim.
        await transport.enqueue(.json(#"{"error":"A list title is required","code":"bad_request"}"#, status: 400))

        do {
            _ = try await client.send(Materialize.create(MaterializeRequest(
                target: .list, source: .messages(ids: ["m1"]),
                listConfig: MaterializeListConfig(title: "", fields: [])
            )))
            XCTFail("Expected a thrown APIError")
        } catch APIError.badRequest(let serverMessage) {
            XCTAssertEqual(serverMessage, "A list title is required")
        }
    }

    // MARK: - Upstream failure

    func test_givenUnavailableSource_whenSent_thenThrowsNotFound() async throws {
        let (client, transport) = makeClient()
        // The live 404 when a source id does not resolve.
        await transport.enqueue(.json(#"{"error":"One or more messages are unavailable","code":"not_found"}"#, status: 404))

        do {
            _ = try await client.send(Materialize.create(MaterializeRequest(
                target: .doc, source: .messages(ids: ["missing"]),
                docConfig: MaterializeDocConfig(title: "Doc")
            )))
            XCTFail("Expected a thrown APIError")
        } catch APIError.notFound(let serverMessage) {
            XCTAssertEqual(serverMessage, "One or more messages are unavailable")
        }
    }

    // MARK: - Empty / boundary

    /// The live 201 nests the created object; a flat `listId` must still decode
    /// so a later server-side flattening does not break the client.
    func test_givenFlatIdResponse_whenDecoded_thenStillSurfacesTheId() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"listId":"l-flat"}"#, status: 201))

        let response = try await client.send(Materialize.create(MaterializeRequest(
            target: .list, source: .messages(ids: ["m1"]),
            listConfig: MaterializeListConfig(
                title: "T", fields: [MaterializeField(propertyKey: "content", propertyName: "Content")])
        )))

        XCTAssertEqual(response.listId, "l-flat")
        XCTAssertNil(response.list)
    }

    func test_givenEmptyResponseBody_whenDecoded_thenEveryIdIsNil() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{}"#, status: 201))

        let response = try await client.send(Materialize.create(MaterializeRequest(
            target: .doc, source: .lists(ids: []), docConfig: MaterializeDocConfig(title: "Doc")
        )))

        XCTAssertNil(response.listId)
        XCTAssertNil(response.documentId)
    }
}
