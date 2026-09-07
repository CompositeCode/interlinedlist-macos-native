import Foundation
import InterlinedKit

// MARK: - AIServicing

/// The AI surface (work-consolidation.md G15) — the composer writing assistant,
/// series planning, AI list templates, and AI documents.
///
/// The shape is deliberately two-step and mirrors the server's own: `suggest`
/// runs a feature and returns a **preview** that persists nothing, and `generate`
/// takes a previewed artifact back and persists it. The App layer shows the
/// preview with an explicit Confirm, so a user is never billed for something they
/// did not accept and nothing is written behind their back.
///
/// **Every call spends real money** — a quota unit and a call against the user's
/// own provider key — so `suggest` refuses locally before it spends: it checks
/// availability, and it checks the feature's minimum word count.
public protocol AIServicing: Sendable {
    /// Whether AI can be used, and if not, why. Cheap; call it before offering
    /// the menu so a refusal can be explained rather than thrown on use.
    func availability() async throws -> AIAvailability

    /// Runs the composer assistant over a draft.
    func assist(draft: String, action: AIWritingAction) async throws -> AISuggestion

    /// Plans a series of short posts from a brief.
    /// - Parameter channels: cross-post destinations, so the server sizes each
    ///   part to the smallest selected platform limit.
    func planMessageSeries(brief: String, channels: [String]) async throws -> AISuggestion

    /// Plans a series of documents from a brief.
    func planArticleSeries(brief: String) async throws -> AISuggestion

    /// Drafts a list schema plus starter rows from a description.
    func draftListTemplate(describing description: String) async throws -> AISuggestion

    /// Drafts a document.
    func draftDocument(prompt: String, mode: AIDocumentMode) async throws -> AISuggestion

    /// Persists a previewed artifact.
    /// - Parameters:
    ///   - crossPost: message-series only — the composer's cross-post selection.
    ///   - scheduleImmediately: message-series only — post on a schedule instead
    ///     of collecting the series into a list.
    func confirm(
        _ suggestion: AISuggestion,
        crossPost: [String: Bool]?,
        scheduleImmediately: Bool?
    ) async throws -> AIGenerationResult
}

public extension AIServicing {

    /// Confirms a suggestion that needs no series options.
    func confirm(_ suggestion: AISuggestion) async throws -> AIGenerationResult {
        try await confirm(suggestion, crossPost: nil, scheduleImmediately: nil)
    }
}

// MARK: - AIService

public final class AIService: AIServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    // MARK: Availability

    public func availability() async throws -> AIAvailability {
        AIAvailability(from: try await api.send(AI.status()))
    }

    // MARK: Suggest

    public func assist(draft: String, action: AIWritingAction) async throws -> AISuggestion {
        try await suggest(
            feature: .writingAssist,
            input: draft,
            context: AISuggestContext(action: action.wireAction)
        )
    }

    public func planMessageSeries(brief: String, channels: [String]) async throws -> AISuggestion {
        try await suggest(
            feature: .messageSeries,
            input: brief,
            context: channels.isEmpty ? nil : AISuggestContext(channels: channels)
        )
    }

    public func planArticleSeries(brief: String) async throws -> AISuggestion {
        try await suggest(feature: .articleSeries, input: brief, context: nil)
    }

    public func draftListTemplate(describing description: String) async throws -> AISuggestion {
        try await suggest(feature: .listTemplate, input: description, context: nil)
    }

    public func draftDocument(prompt: String, mode: AIDocumentMode) async throws -> AISuggestion {
        try await suggest(feature: .document, input: prompt, context: mode.wireContext)
    }

    // MARK: Generate

    public func confirm(
        _ suggestion: AISuggestion,
        crossPost: [String: Bool]?,
        scheduleImmediately: Bool?
    ) async throws -> AIGenerationResult {
        let response = try await mappingAIErrors {
            try await api.send(AI.generate(AIGenerateRequest(
                feature: suggestion.feature.wireFeature,
                // The server's own artifact, echoed back unchanged.
                artifact: suggestion.token.dto,
                crossPost: crossPost,
                scheduleImmediately: scheduleImmediately
            )))
        }
        return AIGenerationResult(from: response)
    }

    // MARK: - Internals

    /// One place where a spend happens, so the two local refusals — unavailable
    /// and too-short — cannot be forgotten by a new call site.
    private func suggest(
        feature: AIFeature,
        input: String,
        context: AISuggestContext?
    ) async throws -> AISuggestion {
        let availability = try await availability()
        if let reason = availability.unavailableReason {
            if let quota = availability.quota, !quota.hasRemaining {
                throw AIError.quotaExhausted(dailyLimit: quota.dailyLimit)
            }
            throw AIError.unavailable(reason: reason)
        }

        guard Self.wordCount(input) >= feature.minimumWords else {
            throw AIError.inputTooShort(minimumWords: feature.minimumWords)
        }

        let response = try await mappingAIErrors {
            try await api.send(AI.suggest(AISuggestRequest(
                feature: feature.wireFeature, input: input, context: context
            )))
        }

        guard let suggestion = AISuggestion(from: response, feature: feature) else {
            throw AIError.providerRejected(message: "The AI service returned no result.")
        }
        return suggestion
    }

    /// Words, counted the way the web app counts them, so the client-side
    /// minimums match the ones the other client enforces.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Translates the two failures worth their own presentation: the provider
    /// refusing (a live `502 provider_error`, not the user's fault) and the quota
    /// running out mid-session. Everything else propagates as `APIError`.
    private func mappingAIErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as APIError {
            if let mapped = Self.aiError(from: error) { throw mapped }
            throw error
        }
    }

    static func aiError(from error: APIError) -> AIError? {
        switch error {
        case .httpStatus(let code, let message) where code == 502:
            return .providerRejected(message: message)
        case .rateLimited(let message, _):
            return .providerRejected(message: message)
        case .forbidden(let message):
            return .unavailable(reason: message ?? "AI features are part of a subscription.")
        default:
            return nil
        }
    }
}
