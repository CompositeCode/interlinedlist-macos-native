import XCTest
@testable import InterlinedKit

/// BDD tests for the AI endpoints (work-consolidation.md G15).
///
/// The fixtures below are the shapes captured from the live route and from the
/// web client's own rendering code on 2026-09-05, so a server-side rename shows
/// up here as a failure rather than as a silent nil in the UI.
final class AIEndpointTests: XCTestCase {

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

    // MARK: - Builder shape

    func test_givenAIBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(AI.status().method, .get)
        XCTAssertEqual(AI.status().path, "/api/ai/status")
        XCTAssertEqual(AI.status().auth, .bearer)

        let suggest = AI.suggest(AISuggestRequest(feature: .writingAssist, input: "draft"))
        XCTAssertEqual(suggest.method, .post)
        XCTAssertEqual(suggest.path, "/api/ai/suggest")
        XCTAssertEqual(suggest.auth, .bearer)

        let generate = AI.generate(AIGenerateRequest(feature: .poweredDocument, artifact: AIArtifactDTO()))
        XCTAssertEqual(generate.method, .post)
        XCTAssertEqual(generate.path, "/api/ai/generate")
        XCTAssertEqual(generate.auth, .bearer)
    }

    func test_givenFeatureEnum_whenSerialized_thenUsesTheLiveWireNames() {
        XCTAssertEqual(AIFeature.allCases.map(\.rawValue),
                       ["writing_assist", "message_series", "article_series",
                        "powered_template", "powered_document"])
        XCTAssertEqual(AIWritingAction.allCases.map(\.rawValue),
                       ["rewrite", "tighten", "expand", "grammar", "thread", "tags"])
        XCTAssertEqual(AIDocumentMode.allCases.map(\.rawValue),
                       ["article", "from_list", "from_article", "research_url"])
    }

    // MARK: - Happy path

    func test_givenStatusBody_whenSent_thenDecodesSubscriberProvidersAndQuota() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "subscriber": true, "providers": ["anthropic"],
          "defaultModels": { "anthropic": "claude-sonnet-5" },
          "quota": { "usedToday": 3, "dailyLimit": 50, "remaining": 47 } }
        """#))

        let dto = try await client.send(AI.status())

        XCTAssertEqual(dto.subscriber, true)
        XCTAssertEqual(dto.providers, ["anthropic"])
        XCTAssertEqual(dto.defaultModels?["anthropic"], "claude-sonnet-5")
        XCTAssertEqual(dto.quota?.remaining, 47)
        XCTAssertEqual(dto.quota?.dailyLimit, 50)
    }

    func test_givenWritingAssist_whenSuggestSent_thenEncodesFeatureInputAndAction() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"artifact":{"kind":"text","content":"tighter"}}"#))

        _ = try await client.send(AI.suggest(AISuggestRequest(
            feature: .writingAssist, input: "a long draft", context: .writing(.tighten)
        )))

        let received = await transport.received
        let body = try XCTUnwrap(received.first?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["feature"] as? String, "writing_assist")
        XCTAssertEqual(json?["input"] as? String, "a long draft")
        XCTAssertEqual((json?["context"] as? [String: Any])?["action"] as? String, "tighten")
    }

    /// Fixtures below are trimmed copies of real 2026-09-05 `suggest` responses,
    /// one call per feature, so a server-side rename fails here rather than
    /// silently nil-ing out in the preview sheet.
    func test_givenEachLiveArtifact_whenDecoded_thenExposesItsOwnPayload() async throws {
        let (client, transport) = makeClient()

        // writing_assist / tighten — note kind is "message", not "text".
        await transport.enqueue(.json(#"""
        { "ok": true, "feature": "writing_assist",
          "artifact": { "kind": "message", "content": "This draft could be shortened." },
          "usage": { "inputTokens": 128, "outputTokens": 25, "model": "claude-sonnet-5" },
          "quota": { "usedToday": 1, "dailyLimit": 50 } }
        """#))
        let rewrite = try await client.send(AI.suggest(AISuggestRequest(
            feature: .writingAssist, input: "x", context: .writing(.tighten))))
        XCTAssertEqual(rewrite.ok, true)
        XCTAssertEqual(rewrite.artifact?.kind, "message")
        XCTAssertEqual(rewrite.artifact?.content, "This draft could be shortened.")
        XCTAssertEqual(rewrite.usage?.model, "claude-sonnet-5")
        XCTAssertEqual(rewrite.usage?.outputTokens, 25)
        XCTAssertEqual(rewrite.quota?.usedToday, 1)
        XCTAssertEqual(rewrite.quota?.dailyLimit, 50)

        // writing_assist / tags
        await transport.enqueue(.json(#"""
        { "ok": true, "artifact": { "kind": "tags", "tags": ["SwiftUI", "macOS"] } }
        """#))
        let tags = try await client.send(AI.suggest(AISuggestRequest(
            feature: .writingAssist, input: "x", context: .writing(.tags))))
        XCTAssertEqual(tags.artifact?.tags, ["SwiftUI", "macOS"])

        // message_series
        await transport.enqueue(.json(#"""
        { "ok": true, "artifact": { "kind": "message_series", "listTitle": "Shipping",
          "items": [ { "order": 1, "content": "First", "crossPostTargets": ["bluesky"] },
                     { "order": 2, "content": "Second", "crossPostTargets": [] } ] } }
        """#))
        let series = try await client.send(AI.suggest(AISuggestRequest(
            feature: .messageSeries, input: "x", context: .series(channels: ["Bluesky"]))))
        XCTAssertEqual(series.artifact?.listTitle, "Shipping")
        XCTAssertEqual(series.artifact?.items?.compactMap(\.order), [1, 2])
        XCTAssertEqual(series.artifact?.items?.first?.crossPostTargets, ["bluesky"])

        // powered_template — the drafted schema plus starter rows
        await transport.enqueue(.json(#"""
        { "ok": true, "artifact": { "kind": "list", "title": "Talks", "description": "CFPs",
          "dsl": { "name": "Talks", "description": "CFPs",
                   "fields": [ { "key": "event", "type": "text", "label": "Event Name",
                                 "required": true, "displayOrder": 0 } ] },
          "rows": [ { "event": "PyCon US", "status": "Submitted" } ] } }
        """#))
        let template = try await client.send(AI.suggest(AISuggestRequest(feature: .poweredTemplate, input: "x")))
        XCTAssertEqual(template.artifact?.kind, "list")
        let field = try XCTUnwrap(template.artifact?.dsl?.fields?.first)
        XCTAssertEqual(field.key, "event")
        XCTAssertEqual(field.label, "Event Name")
        XCTAssertEqual(field.required, true)
        XCTAssertEqual(field.displayOrder, 0)
        XCTAssertEqual(template.artifact?.rows?.first?["event"], .string("PyCon US"))

        // powered_document
        await transport.enqueue(.json(#"""
        { "ok": true, "artifact": { "kind": "document", "title": "Contracts",
          "markdown": "# Contracts", "outline": ["Intro", "Body"], "isPublic": false } }
        """#))
        let doc = try await client.send(AI.suggest(AISuggestRequest(feature: .poweredDocument, input: "x")))
        XCTAssertEqual(doc.artifact?.title, "Contracts")
        XCTAssertEqual(doc.artifact?.outline, ["Intro", "Body"])
        XCTAssertEqual(doc.artifact?.isPublic, false)
    }

    func test_givenProviderRejection_whenSuggestSent_thenSurfacesProviderError() async throws {
        let (client, transport) = makeClient()
        // Observed live on an article_series probe: the provider itself refused.
        await transport.enqueue(.json(#"{"error":"The AI provider rejected the request.","code":"provider_error"}"#, status: 502))

        do {
            _ = try await client.send(AI.suggest(AISuggestRequest(feature: .articleSeries, input: "x")))
            XCTFail("Expected a thrown APIError")
        } catch APIError.httpStatus(let code, let serverMessage) {
            XCTAssertEqual(code, 502)
            XCTAssertEqual(serverMessage, "The AI provider rejected the request.")
        }
    }

    func test_givenArtifactWithUnmodelledMembers_whenEchoedToGenerate_thenRoundTripsVerbatim() async throws {
        let (client, transport) = makeClient()
        // `tone` and `sourceIds` are members this client does not model. They must
        // survive the suggest -> generate round-trip, or a confirmed artifact would
        // be silently downgraded on the way back to the server.
        await transport.enqueue(.json(#"""
        {"ok":true,"artifact":{"title":"Doc","markdown":"# Doc","tone":"wry","sourceIds":["a","b"]}}
        """#))
        let suggested = try await client.send(AI.suggest(AISuggestRequest(feature: .poweredDocument, input: "x")))
        let artifact = try XCTUnwrap(suggested.artifact)

        await transport.enqueue(.json(#"{"created":{"documentId":"d-1"}}"#))
        let response = try await client.send(AI.generate(AIGenerateRequest(feature: .poweredDocument, artifact: artifact)))

        let received = await transport.received
        let body = try XCTUnwrap(received.last?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let echoed = try XCTUnwrap(json?["artifact"] as? [String: Any])
        XCTAssertEqual(echoed["tone"] as? String, "wry")
        XCTAssertEqual(echoed["sourceIds"] as? [String], ["a", "b"])
        XCTAssertEqual(echoed["title"] as? String, "Doc")
        XCTAssertEqual(response.created?.documentId, "d-1")
    }

    func test_givenScheduledSeries_whenGenerateSent_thenEncodesCrossPostAndScheduleFlag() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"created":{"scheduledMessageIds":["m1","m2"],"firstScheduledAt":"2026-09-06T01:00:00.000Z"}}
        """#))

        let response = try await client.send(AI.generate(AIGenerateRequest(
            feature: .messageSeries,
            artifact: AIArtifactDTO(items: [.init(content: "one")]),
            crossPost: ["bluesky": true],
            scheduleImmediately: true
        )))

        let received = await transport.received
        let body = try XCTUnwrap(received.first?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["feature"] as? String, "message_series")
        XCTAssertEqual(json?["scheduleImmediately"] as? Bool, true)
        XCTAssertEqual((json?["crossPost"] as? [String: Any])?["bluesky"] as? Bool, true)
        XCTAssertEqual(response.created?.scheduledMessageIds, ["m1", "m2"])
        XCTAssertEqual(response.created?.firstScheduledAt,
                       ISO8601DateFormatter().date(from: "2026-09-06T01:00:00Z"))
    }

    // MARK: - Invalid input

    func test_givenUnknownFeatureRejection_whenSuggestSent_thenSurfacesServerMessage() async throws {
        let (client, transport) = makeClient()
        // The live 422 for an unknown/missing feature, verbatim.
        await transport.enqueue(.json(#"{"error":"Unknown or missing feature.","code":"invalid_input"}"#, status: 422))

        do {
            _ = try await client.send(AI.suggest(AISuggestRequest(feature: .writingAssist, input: "")))
            XCTFail("Expected a thrown APIError")
        } catch APIError.httpStatus(let code, let serverMessage) {
            // 422 has no dedicated case, so it lands in `httpStatus`.
            XCTAssertEqual(code, 422)
            XCTAssertEqual(serverMessage, "Unknown or missing feature.")
        }
    }

    // MARK: - Upstream failure

    func test_givenServerError_whenSuggestSent_thenThrows() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"provider unavailable"}"#, status: 500))

        do {
            _ = try await client.send(AI.suggest(AISuggestRequest(feature: .articleSeries, input: "x")))
            XCTFail("Expected a thrown APIError")
        } catch APIError.httpStatus(let code, _) {
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: - Empty / boundary

    func test_givenEmptyBodies_whenDecoded_thenEveryMemberIsNilRatherThanThrowing() async throws {
        let (client, transport) = makeClient()

        await transport.enqueue(.json(#"{}"#))
        let status = try await client.send(AI.status())
        XCTAssertNil(status.subscriber)
        XCTAssertNil(status.quota)

        await transport.enqueue(.json(#"{}"#))
        let suggest = try await client.send(AI.suggest(AISuggestRequest(feature: .poweredTemplate, input: "x")))
        XCTAssertNil(suggest.artifact)

        await transport.enqueue(.json(#"{"created":{}}"#))
        let generate = try await client.send(AI.generate(AIGenerateRequest(feature: .poweredTemplate, artifact: AIArtifactDTO())))
        XCTAssertNotNil(generate.created)
        XCTAssertNil(generate.created?.listId)
    }

    func test_givenNoContext_whenSuggestSent_thenContextKeyIsOmittedEntirely() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"artifact":{}}"#))

        _ = try await client.send(AI.suggest(AISuggestRequest(feature: .articleSeries, input: "brief")))

        let received = await transport.received
        let body = try XCTUnwrap(received.first?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertNil(json?["context"], "A nil context must not serialize as null")
    }
}
