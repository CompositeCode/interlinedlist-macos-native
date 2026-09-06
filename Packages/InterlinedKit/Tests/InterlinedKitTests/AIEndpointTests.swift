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

    func test_givenEachArtifactKind_whenDecoded_thenExposesItsOwnPayload() async throws {
        let (client, transport) = makeClient()

        await transport.enqueue(.json(#"{"artifact":{"kind":"tags","tags":["swift","macos"]}}"#))
        let tags = try await client.send(AI.suggest(AISuggestRequest(feature: .writingAssist, input: "x")))
        XCTAssertEqual(tags.artifact?.kind, "tags")
        XCTAssertEqual(tags.artifact?.tags, ["swift", "macos"])

        await transport.enqueue(.json(#"{"artifact":{"kind":"thread","parts":["one","two"]}}"#))
        let thread = try await client.send(AI.suggest(AISuggestRequest(feature: .writingAssist, input: "x")))
        XCTAssertEqual(thread.artifact?.parts, ["one", "two"])

        await transport.enqueue(.json(#"{"artifact":{"items":[{"content":"part 1"},{"content":"part 2"}]}}"#))
        let series = try await client.send(AI.suggest(AISuggestRequest(feature: .messageSeries, input: "x")))
        XCTAssertEqual(series.artifact?.items?.compactMap(\.content), ["part 1", "part 2"])

        await transport.enqueue(.json(#"{"artifact":{"documents":[{"title":"Part one"}]}}"#))
        let articles = try await client.send(AI.suggest(AISuggestRequest(feature: .articleSeries, input: "x")))
        XCTAssertEqual(articles.artifact?.documents?.compactMap(\.title), ["Part one"])

        await transport.enqueue(.json(#"""
        {"artifact":{"title":"On Swift","outline":["Intro","Body"],"markdown":"# On Swift"}}
        """#))
        let doc = try await client.send(AI.suggest(AISuggestRequest(feature: .poweredDocument, input: "x")))
        XCTAssertEqual(doc.artifact?.title, "On Swift")
        XCTAssertEqual(doc.artifact?.outline, ["Intro", "Body"])
        XCTAssertEqual(doc.artifact?.markdown, "# On Swift")
    }

    func test_givenArtifactWithUnmodelledMembers_whenEchoedToGenerate_thenRoundTripsVerbatim() async throws {
        let (client, transport) = makeClient()
        // `tone` and `sourceIds` are members this client does not model. They must
        // survive the suggest -> generate round-trip, or a confirmed artifact would
        // be silently downgraded on the way back to the server.
        await transport.enqueue(.json(#"""
        {"artifact":{"title":"Doc","markdown":"# Doc","tone":"wry","sourceIds":["a","b"]}}
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
        XCTAssertEqual(response.created?.firstScheduledAt, "2026-09-06T01:00:00.000Z")
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
