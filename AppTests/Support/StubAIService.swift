// StubAIService
//
// Deterministic `AIServicing` stub for App-layer view-model tests of the AI
// surface (work-consolidation.md G15). Mirrors the project's other stubs: an
// actor with FIFO outcome queues plus a recorded-call log.
//
// The call log matters more here than elsewhere — every real `suggest` spends a
// quota unit and bills the user's own provider key, so "did this path call at
// all?" is a correctness question, not a curiosity.

import Foundation
import InterlinedDomain

struct RecordedAICall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case availability
        case assist(action: AIWritingAction, draft: String)
        case messageSeries(brief: String, channels: [String])
        case articleSeries(brief: String)
        case listTemplate(description: String)
        case document(prompt: String)
        case confirm(feature: AIFeature, scheduleImmediately: Bool?)
    }
    let kind: Kind
}

actor StubAIService: AIServicing {

    private var availabilityOutcomes: [Result<AIAvailability, Error>] = []
    private var suggestOutcomes: [Result<AISuggestion, Error>] = []
    private var confirmOutcomes: [Result<AIGenerationResult, Error>] = []

    private(set) var recorded: [RecordedAICall] = []

    // MARK: Programmable enqueue helpers

    func enqueueAvailability(_ value: AIAvailability) { availabilityOutcomes.append(.success(value)) }
    func enqueueAvailability(failure error: Error) { availabilityOutcomes.append(.failure(error)) }

    func enqueueSuggestion(_ value: AISuggestion) { suggestOutcomes.append(.success(value)) }
    func enqueueSuggestion(failure error: Error) { suggestOutcomes.append(.failure(error)) }

    func enqueueConfirm(_ value: AIGenerationResult) { confirmOutcomes.append(.success(value)) }
    func enqueueConfirm(failure error: Error) { confirmOutcomes.append(.failure(error)) }

    /// Convenience: an entitled account with a provider configured.
    static func available(usedToday: Int = 1, dailyLimit: Int = 50) -> AIAvailability {
        AIAvailability(
            isSubscriber: true,
            providers: ["anthropic"],
            defaultModels: ["anthropic": "claude-sonnet-5"],
            quota: AIQuota(usedToday: usedToday, dailyLimit: dailyLimit)
        )
    }

    // MARK: AIServicing

    func availability() async throws -> AIAvailability {
        recorded.append(.init(kind: .availability))
        return try next(&availabilityOutcomes, label: "availability")
    }

    func assist(draft: String, action: AIWritingAction) async throws -> AISuggestion {
        recorded.append(.init(kind: .assist(action: action, draft: draft)))
        return try next(&suggestOutcomes, label: "assist")
    }

    func planMessageSeries(brief: String, channels: [String]) async throws -> AISuggestion {
        recorded.append(.init(kind: .messageSeries(brief: brief, channels: channels)))
        return try next(&suggestOutcomes, label: "messageSeries")
    }

    func planArticleSeries(brief: String) async throws -> AISuggestion {
        recorded.append(.init(kind: .articleSeries(brief: brief)))
        return try next(&suggestOutcomes, label: "articleSeries")
    }

    func draftListTemplate(describing description: String) async throws -> AISuggestion {
        recorded.append(.init(kind: .listTemplate(description: description)))
        return try next(&suggestOutcomes, label: "listTemplate")
    }

    func draftDocument(prompt: String, mode: AIDocumentMode) async throws -> AISuggestion {
        recorded.append(.init(kind: .document(prompt: prompt)))
        return try next(&suggestOutcomes, label: "document")
    }

    func confirm(
        _ suggestion: AISuggestion,
        crossPost: [String: Bool]?,
        scheduleImmediately: Bool?
    ) async throws -> AIGenerationResult {
        recorded.append(.init(kind: .confirm(
            feature: suggestion.feature, scheduleImmediately: scheduleImmediately
        )))
        return try next(&confirmOutcomes, label: "confirm")
    }

    // MARK: - Internals

    private func next<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else { throw UnprogrammedAICall(label: label) }
        return try queue.removeFirst().get()
    }
}

/// Thrown when a test exercises a path the stub was not programmed for — a
/// louder failure than returning a default would be.
struct UnprogrammedAICall: Error, CustomStringConvertible {
    let label: String
    var description: String { "StubAIService: no queued outcome for \(label)" }
}
