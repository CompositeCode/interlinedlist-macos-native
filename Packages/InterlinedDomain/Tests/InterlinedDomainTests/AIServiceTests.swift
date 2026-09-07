import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD tests for `AIService` (work-consolidation.md G15).
///
/// The JSON fixtures are trimmed copies of real 2026-09-05 responses. Several
/// tests assert on how many requests reached the stub, because every `suggest`
/// spends a quota unit and bills the user's own provider key — a refusal that
/// still calls the server is a real defect, not a cosmetic one.
final class AIServiceTests: XCTestCase {

    private let availableStatus = #"""
    { "subscriber": true, "providers": ["anthropic"],
      "defaultModels": { "anthropic": "claude-sonnet-5" },
      "quota": { "usedToday": 3, "dailyLimit": 50, "remaining": 47 } }
    """#

    private func makeService(_ api: StubAPIClient) -> AIService {
        AIService(api: api)
    }

    // MARK: - Availability

    func test_givenSubscriberWithProvider_whenAvailabilityFetched_thenIsAvailable() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)

        let availability = try await makeService(api).availability()

        XCTAssertTrue(availability.isAvailable)
        XCTAssertNil(availability.unavailableReason)
        XCTAssertEqual(availability.providers, ["anthropic"])
        XCTAssertEqual(availability.defaultModels["anthropic"], "claude-sonnet-5")
        XCTAssertEqual(availability.quota?.remaining, 47)
    }

    func test_givenSubscriberWithNoProviderKey_whenAvailabilityFetched_thenExplainsWhy() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"subscriber": true, "providers": []}"#)

        let availability = try await makeService(api).availability()

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(
            availability.unavailableReason,
            "Add your own AI provider key in Settings on interlinedlist.com to use AI features."
        )
    }

    func test_givenNonSubscriber_whenAvailabilityFetched_thenReportsSubscriptionReason() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"subscriber": false, "providers": ["anthropic"]}"#)

        let availability = try await makeService(api).availability()

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.unavailableReason, "AI features are part of a subscription.")
    }

    func test_givenEmptyStatusBody_whenAvailabilityFetched_thenTreatsAccountAsUnentitled() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{}"#)

        let availability = try await makeService(api).availability()

        // The safe direction: never offer a control the server will refuse.
        XCTAssertFalse(availability.isAvailable)
    }

    // MARK: - Happy path

    func test_givenDraft_whenAssistRuns_thenReturnsTheRewrittenMessage() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(json: #"""
        { "ok": true, "feature": "writing_assist",
          "artifact": { "kind": "message", "content": "Tighter draft." },
          "usage": { "inputTokens": 128, "outputTokens": 25, "model": "claude-sonnet-5" },
          "quota": { "usedToday": 4, "dailyLimit": 50 } }
        """#)

        let suggestion = try await makeService(api).assist(draft: "a long rambling draft", action: .tighten)

        XCTAssertEqual(suggestion.feature, .writingAssist)
        XCTAssertEqual(suggestion.artifact, .message("Tighter draft."))
        XCTAssertEqual(suggestion.usage?.model, "claude-sonnet-5")
        XCTAssertEqual(suggestion.quota?.usedToday, 4)

        let paths = await api.recorded.map(\.path)
        XCTAssertEqual(paths, ["/api/ai/status", "/api/ai/suggest"])
    }

    func test_givenEachArtifactShape_whenProjected_thenMapsToItsDomainCase() async throws {
        let cases: [(String, InterlinedDomain.AIFeature, InterlinedDomain.AIArtifact)] = [
            (#"{"artifact":{"kind":"tags","tags":["swift","macos"]}}"#,
             InterlinedDomain.AIFeature.writingAssist, InterlinedDomain.AIArtifact.tags(["swift", "macos"])),
            (#"{"artifact":{"kind":"thread","parts":["one","two"]}}"#,
             InterlinedDomain.AIFeature.writingAssist, InterlinedDomain.AIArtifact.thread(parts: ["one", "two"])),
            (#"{"artifact":{"kind":"document","title":"T","markdown":"Body text","outline":["a"],"isPublic":false}}"#,
             InterlinedDomain.AIFeature.document,
             InterlinedDomain.AIArtifact.document(AIDocumentDraft(title: "T", markdown: "Body text", outline: ["a"], isPublic: false)))
        ]

        for (json, feature, expected) in cases {
            let api = StubAPIClient()
            await api.enqueue(json: availableStatus)
            await api.enqueue(json: json)

            let suggestion: AISuggestion
            switch feature {
            case .writingAssist:
                suggestion = try await makeService(api).assist(draft: "some draft here", action: .rewrite)
            default:
                suggestion = try await makeService(api).draftDocument(prompt: "a topic", mode: .article)
            }
            XCTAssertEqual(suggestion.artifact, expected)
        }
    }

    func test_givenSeriesArtifact_whenProjected_thenOrdersAndCarriesCrossPostTargets() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(json: #"""
        { "artifact": { "kind": "message_series", "listTitle": "Shipping",
          "items": [ { "order": 1, "content": "First", "crossPostTargets": ["bluesky"] },
                     { "order": 2, "content": "Second" } ] } }
        """#)

        let suggestion = try await makeService(api)
            .planMessageSeries(brief: "a brief long enough to clear the ten word minimum easily", channels: ["Bluesky"])

        guard case .messageSeries(let listTitle, let items) = suggestion.artifact else {
            return XCTFail("Expected a message series, got \(suggestion.artifact)")
        }
        XCTAssertEqual(listTitle, "Shipping")
        XCTAssertEqual(items.map(\.order), [1, 2])
        XCTAssertEqual(items.first?.crossPostTargets, ["bluesky"])
        XCTAssertEqual(items.last?.crossPostTargets, [], "a missing target list reads as none, not nil")
    }

    func test_givenListTemplateArtifact_whenProjected_thenSortsFieldsAndRendersRows() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(json: #"""
        { "artifact": { "kind": "list", "title": "Talks", "description": "CFPs",
          "dsl": { "name": "Talks", "fields": [
              { "key": "status", "type": "select", "label": "Status", "displayOrder": 1 },
              { "key": "event", "type": "text", "label": "Event", "required": true, "displayOrder": 0 } ] },
          "rows": [ { "event": "PyCon", "status": "Submitted", "count": 3 } ] } }
        """#)

        let suggestion = try await makeService(api).draftListTemplate(describing: "a talks tracker")

        guard case .listTemplate(let draft) = suggestion.artifact else {
            return XCTFail("Expected a list template, got \(suggestion.artifact)")
        }
        XCTAssertEqual(draft.title, "Talks")
        XCTAssertEqual(draft.fields.map(\.key), ["event", "status"], "fields sort by displayOrder")
        XCTAssertEqual(draft.fields.first?.isRequired, true)
        XCTAssertEqual(draft.rows.first?["event"], "PyCon")
        XCTAssertEqual(draft.rows.first?["count"], "3", "non-string cells render for display")
    }

    func test_givenUnrecognisedArtifact_whenProjected_thenReportsUnknownRatherThanFailing() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(json: #"{"artifact":{"kind":"something_new"}}"#)

        let suggestion = try await makeService(api).draftListTemplate(describing: "x")

        XCTAssertEqual(suggestion.artifact, .unknown(kind: "something_new"))
    }

    // MARK: - Invalid input

    func test_givenDraftBelowTheMinimum_whenAssistRuns_thenRefusesWithoutSpendingACall() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)

        do {
            _ = try await makeService(api).assist(draft: "hi", action: .rewrite)
            XCTFail("Expected AIError.inputTooShort")
        } catch AIError.inputTooShort(let minimum) {
            XCTAssertEqual(minimum, 2)
        }

        let paths = await api.recorded.map(\.path)
        XCTAssertEqual(paths, ["/api/ai/status"], "no suggest call may be spent on a too-short draft")
    }

    func test_givenBriefBelowTheSeriesMinimum_whenSeriesPlanned_thenRefusesWithoutSpendingACall() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)

        do {
            _ = try await makeService(api).planMessageSeries(brief: "too short", channels: [])
            XCTFail("Expected AIError.inputTooShort")
        } catch AIError.inputTooShort(let minimum) {
            XCTAssertEqual(minimum, 10)
        }

        let count = await api.recorded.count
        XCTAssertEqual(count, 1)
    }

    func test_givenUnavailableAccount_whenAssistRuns_thenRefusesWithoutSpendingACall() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"subscriber": false}"#)

        do {
            _ = try await makeService(api).assist(draft: "a perfectly long draft", action: .rewrite)
            XCTFail("Expected AIError.unavailable")
        } catch AIError.unavailable(let reason) {
            XCTAssertEqual(reason, "AI features are part of a subscription.")
        }

        let paths = await api.recorded.map(\.path)
        XCTAssertEqual(paths, ["/api/ai/status"])
    }

    func test_givenSpentQuota_whenAssistRuns_thenReportsQuotaExhausted() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "subscriber": true, "providers": ["anthropic"],
          "quota": { "usedToday": 50, "dailyLimit": 50, "remaining": 0 } }
        """#)

        do {
            _ = try await makeService(api).assist(draft: "a perfectly long draft", action: .rewrite)
            XCTFail("Expected AIError.quotaExhausted")
        } catch AIError.quotaExhausted(let limit) {
            XCTAssertEqual(limit, 50)
        }
    }

    // MARK: - Upstream failure

    func test_givenProviderRejection_whenAssistRuns_thenMapsToProviderRejected() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(failure: .httpStatus(code: 502, serverMessage: "The AI provider rejected the request."))

        do {
            _ = try await makeService(api).assist(draft: "a perfectly long draft", action: .expand)
            XCTFail("Expected AIError.providerRejected")
        } catch AIError.providerRejected(let message) {
            XCTAssertEqual(message, "The AI provider rejected the request.")
        }
    }

    func test_givenServerError_whenAssistRuns_thenPropagatesTheAPIError() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))

        do {
            _ = try await makeService(api).assist(draft: "a perfectly long draft", action: .expand)
            XCTFail("Expected the underlying APIError")
        } catch APIError.httpStatus(let code, _) {
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: - Empty / boundary

    func test_givenResponseWithNoArtifact_whenAssistRuns_thenThrowsRatherThanShowingAnEmptyPreview() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(json: #"{"ok":true}"#)

        do {
            _ = try await makeService(api).assist(draft: "a perfectly long draft", action: .rewrite)
            XCTFail("Expected AIError.providerRejected")
        } catch AIError.providerRejected {
            // Expected.
        }
    }

    // MARK: - Confirm

    func test_givenConfirmedSeries_whenScheduled_thenReportsScheduledMessages() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(json: #"{"artifact":{"kind":"message_series","items":[{"order":1,"content":"one"}]}}"#)
        let service = makeService(api)
        let suggestion = try await service.planMessageSeries(
            brief: "a brief long enough to clear the ten word minimum easily", channels: ["Bluesky"]
        )

        await api.enqueue(json: #"""
        {"created":{"scheduledMessageIds":["m1","m2"],"firstScheduledAt":"2026-09-06T01:00:00.000Z"}}
        """#)
        let result = try await service.confirm(suggestion, crossPost: ["bluesky": true], scheduleImmediately: true)

        guard case .scheduledMessages(let ids, let first) = result else {
            return XCTFail("Expected scheduled messages, got \(result)")
        }
        XCTAssertEqual(ids, ["m1", "m2"])
        XCTAssertEqual(first, ISO8601DateFormatter().date(from: "2026-09-06T01:00:00Z"))
    }

    func test_givenConfirmedDocument_whenGenerated_thenReportsTheDocumentId() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(json: #"{"artifact":{"kind":"document","title":"T","markdown":"Body text"}}"#)
        let service = makeService(api)
        let suggestion = try await service.draftDocument(prompt: "a topic", mode: .article)

        await api.enqueue(json: #"{"created":{"documentId":"d-1"}}"#)
        let result = try await service.confirm(suggestion)

        XCTAssertEqual(result, .document(id: "d-1"))
    }

    func test_givenGenerateWithNoRecognisedId_whenConfirmed_thenReportsPlainCreation() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: availableStatus)
        await api.enqueue(json: #"{"artifact":{"kind":"list","dsl":{"name":"L"}}}"#)
        let service = makeService(api)
        let suggestion = try await service.draftListTemplate(describing: "a list")

        await api.enqueue(json: #"{"created":{}}"#)
        let result = try await service.confirm(suggestion)

        XCTAssertEqual(result, .created)
    }

    // MARK: - Word counting

    func test_givenVariousDrafts_whenCounted_thenMatchesTheWebAppsWhitespaceSplit() {
        XCTAssertEqual(AIService.wordCount(""), 0)
        XCTAssertEqual(AIService.wordCount("   "), 0)
        XCTAssertEqual(AIService.wordCount("one"), 1)
        XCTAssertEqual(AIService.wordCount("one  two\nthree\tfour"), 4)
    }
}
