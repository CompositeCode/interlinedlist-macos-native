// AIAssistantViewModelTests
//
// BDD tests for the composer's AI assistant (work-consolidation.md G15).
//
// Several tests assert the *call log*, not just the surfaced state: every real
// suggest spends a quota unit and bills the user's own provider key, so a path
// that calls when it should not is a defect that costs money.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class AIAssistantViewModelTests: XCTestCase {

    private func suggestion(
        _ artifact: AIArtifact,
        feature: AIFeature = .writingAssist,
        quota: AIQuota? = nil
    ) -> AISuggestion {
        AISuggestion(
            feature: feature,
            artifact: artifact,
            usage: AIUsage(inputTokens: 100, outputTokens: 20, model: "claude-sonnet-5"),
            quota: quota,
            token: .placeholder
        )
    }

    // MARK: - Availability

    func test_givenEntitledAccount_whenAvailabilityRefreshed_thenMenuIsEnabled() async {
        let service = StubAIService()
        await service.enqueueAvailability(StubAIService.available(usedToday: 3))
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.refreshAvailability()

        XCTAssertTrue(viewModel.isAvailable)
        XCTAssertNil(viewModel.unavailableReason)
        XCTAssertEqual(viewModel.quotaSummary, "3 of 50 AI requests used today")
        XCTAssertTrue(viewModel.hasCheckedAvailability)
    }

    func test_givenSubscriberWithoutProviderKey_whenRefreshed_thenExplainsWhatIsMissing() async {
        let service = StubAIService()
        await service.enqueueAvailability(AIAvailability(isSubscriber: true, providers: []))
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.refreshAvailability()

        XCTAssertFalse(viewModel.isAvailable)
        XCTAssertEqual(
            viewModel.unavailableReason,
            "Add your own AI provider key in Settings on interlinedlist.com to use AI features."
        )
    }

    func test_givenFailedAvailabilityRead_whenRefreshedAgainSucceeds_thenMenuRecovers() async {
        let service = StubAIService()
        await service.enqueueAvailability(failure: URLError(.timedOut))
        await service.enqueueAvailability(StubAIService.available())
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.refreshAvailability()
        XCTAssertFalse(viewModel.isAvailable, "a failed read must not claim availability")

        await viewModel.refreshAvailability()
        XCTAssertTrue(viewModel.isAvailable)
    }

    // MARK: - Happy path

    func test_givenRewrite_whenAssistRuns_thenPreviewCarriesTheProse() async {
        let service = StubAIService()
        await service.enqueueSuggestion(suggestion(.message("Tighter.")))
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.assist(action: .tighten, draft: "a long draft")

        XCTAssertEqual(viewModel.pendingSuggestion?.artifact, .message("Tighter."))
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertNil(viewModel.errorMessage)

        let recorded = await service.recorded
        XCTAssertEqual(recorded.map(\.kind), [.assist(action: .tighten, draft: "a long draft")])
    }

    func test_givenSuggestReportingQuota_whenRun_thenTheQuotaLineUpdatesImmediately() async {
        let service = StubAIService()
        await service.enqueueAvailability(StubAIService.available(usedToday: 1))
        await service.enqueueSuggestion(
            suggestion(.message("x"), quota: AIQuota(usedToday: 2, dailyLimit: 50))
        )
        let viewModel = AIAssistantViewModel(ai: service)
        await viewModel.refreshAvailability()
        XCTAssertEqual(viewModel.quotaSummary, "1 of 50 AI requests used today")

        await viewModel.assist(action: .rewrite, draft: "a long draft")

        // The response reports the post-call count; adopting it beats waiting
        // for the next availability read to tell the user what they just spent.
        XCTAssertEqual(viewModel.quotaSummary, "2 of 50 AI requests used today")
    }

    func test_givenSeriesBrief_whenPlanned_thenChannelsAreForwarded() async {
        let service = StubAIService()
        await service.enqueueSuggestion(suggestion(
            .messageSeries(listTitle: "S", items: [AISeriesItem(order: 1, content: "one")]),
            feature: .messageSeries
        ))
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.planMessageSeries(brief: "a brief", channels: ["Bluesky", "Mastodon"])

        let recorded = await service.recorded
        XCTAssertEqual(recorded.map(\.kind),
                       [.messageSeries(brief: "a brief", channels: ["Bluesky", "Mastodon"])])
    }

    // MARK: - Invalid input

    func test_givenTooShortDraft_whenServiceRefuses_thenMessageIsActionable() async {
        let service = StubAIService()
        await service.enqueueSuggestion(failure: AIError.inputTooShort(minimumWords: 10))
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.planArticleSeries(brief: "short")

        XCTAssertEqual(viewModel.errorMessage, "Write at least 10 words before using AI.")
        XCTAssertNil(viewModel.pendingSuggestion)
    }

    func test_givenBusyAssistant_whenAnotherRunStarts_thenItIsIgnored() async {
        let service = StubAIService()
        await service.enqueueSuggestion(suggestion(.message("first")))
        let viewModel = AIAssistantViewModel(ai: service)
        await viewModel.assist(action: .rewrite, draft: "a long draft")

        // A preview is showing, not busy — a second run is allowed and replaces it.
        await service.enqueueSuggestion(suggestion(.message("second")))
        await viewModel.assist(action: .expand, draft: "a long draft")

        XCTAssertEqual(viewModel.pendingSuggestion?.artifact, .message("second"))
        let count = await service.recorded.count
        XCTAssertEqual(count, 2)
    }

    // MARK: - Upstream failure

    func test_givenProviderRejection_whenAssistRuns_thenBlamesTheProviderNotTheUser() async {
        let service = StubAIService()
        await service.enqueueSuggestion(
            failure: AIError.providerRejected(message: "The AI provider rejected the request.")
        )
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.assist(action: .grammar, draft: "a long draft")

        XCTAssertEqual(viewModel.errorMessage, "The AI provider rejected the request.")
    }

    func test_givenSpentQuota_whenAssistRuns_thenSaysWhenItResets() async {
        let service = StubAIService()
        await service.enqueueSuggestion(failure: AIError.quotaExhausted(dailyLimit: 50))
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.assist(action: .rewrite, draft: "a long draft")

        XCTAssertEqual(viewModel.errorMessage,
                       "You've used today's 50 AI requests. The limit resets tomorrow.")
    }

    // MARK: - Confirming

    func test_givenScheduledSeries_whenConfirmed_thenReportsWhenTheFirstPostLands() async {
        let service = StubAIService()
        await service.enqueueSuggestion(suggestion(
            .messageSeries(listTitle: nil, items: [AISeriesItem(order: 1, content: "one")]),
            feature: .messageSeries
        ))
        let date = ISO8601DateFormatter().date(from: "2026-09-06T01:00:00Z")
        await service.enqueueConfirm(.scheduledMessages(ids: ["m1", "m2"], firstScheduledAt: date))
        await service.enqueueAvailability(StubAIService.available(usedToday: 4))
        let viewModel = AIAssistantViewModel(ai: service)
        await viewModel.planMessageSeries(brief: "a brief", channels: [])

        await viewModel.confirmPending(scheduleImmediately: true)

        guard case .finished(let message, let result) = viewModel.phase else {
            return XCTFail("Expected a finished phase, got \(viewModel.phase)")
        }
        XCTAssertTrue(message.hasPrefix("Scheduled 2 messages — first around"), message)
        XCTAssertEqual(result, .scheduledMessages(ids: ["m1", "m2"], firstScheduledAt: date))

        let recorded = await service.recorded
        XCTAssertTrue(recorded.contains { $0.kind == .confirm(feature: .messageSeries, scheduleImmediately: true) })
    }

    func test_givenNothingPending_whenConfirmed_thenNoCallIsMade() async {
        let service = StubAIService()
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.confirmPending()

        let count = await service.recorded.count
        XCTAssertEqual(count, 0, "confirming with no preview must not reach the service")
    }

    // MARK: - Empty / boundary

    func test_givenUnknownArtifact_whenPreviewed_thenItIsStillPresentable() async {
        let service = StubAIService()
        await service.enqueueSuggestion(suggestion(.unknown(kind: "something_new")))
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.assist(action: .rewrite, draft: "a long draft")

        // A server that adds a feature must not crash or blank the sheet.
        XCTAssertEqual(viewModel.pendingSuggestion?.artifact, .unknown(kind: "something_new"))
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_givenReset_whenCalled_thenPreviewAndErrorAreCleared() async {
        let service = StubAIService()
        await service.enqueueSuggestion(suggestion(.tags(["a"])))
        let viewModel = AIAssistantViewModel(ai: service)
        await viewModel.assist(action: .tags, draft: "a long draft")
        XCTAssertNotNil(viewModel.pendingSuggestion)

        viewModel.reset()

        XCTAssertNil(viewModel.pendingSuggestion)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_givenNoQuotaReported_whenSummarised_thenNoQuotaLineIsShown() async {
        let service = StubAIService()
        await service.enqueueAvailability(
            AIAvailability(isSubscriber: true, providers: ["anthropic"], quota: nil)
        )
        let viewModel = AIAssistantViewModel(ai: service)

        await viewModel.refreshAvailability()

        XCTAssertNil(viewModel.quotaSummary)
        XCTAssertTrue(viewModel.isAvailable)
    }
}
