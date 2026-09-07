// AIAssistantViewModel
//
// Drives the composer's AI assistant and the series planners
// (work-consolidation.md G15). Owns the suggest → preview → confirm cycle so the
// views stay declarative: a view asks for an action, watches `phase`, and applies
// an accepted result through `AIAssistantOutcome`.
//
// Two rules shape this type. First, **every run costs the user money** — a quota
// unit and a call against their own provider key — so nothing runs implicitly:
// no run on appear, no retry on failure, no speculative prefetch beyond the free
// availability read. Second, a preview is *never* applied on its own; the user
// confirms, and for series the confirm is what persists anything.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class AIAssistantViewModel {

    /// What the assistant is doing right now.
    enum Phase: Equatable {
        case idle
        /// A suggest call is in flight for this feature.
        case running(AIFeature)
        /// A preview is ready and awaiting the user.
        case preview(AISuggestion)
        /// A confirmed artifact is being persisted.
        case confirming
        /// A confirm finished; the message is user-facing.
        case finished(message: String, result: AIGenerationResult)
        case failed(message: String)
    }

    // MARK: - Inputs

    private let ai: AIServicing

    // MARK: - State

    private(set) var availability: AIAvailability = .unavailable
    private(set) var phase: Phase = .idle

    /// Whether the availability read has happened at least once. Until it has,
    /// the menu shows as loading rather than as unavailable — claiming a feature
    /// is unavailable before asking would be a lie.
    private(set) var hasCheckedAvailability = false

    init(ai: AIServicing) {
        self.ai = ai
    }

    // MARK: - Derived

    var isAvailable: Bool { availability.isAvailable }

    /// A sentence explaining why the assistant is off, or `nil` when it is on.
    var unavailableReason: String? { availability.unavailableReason }

    var isBusy: Bool {
        switch phase {
        case .running, .confirming: return true
        default: return false
        }
    }

    /// The preview awaiting a decision, if any.
    var pendingSuggestion: AISuggestion? {
        if case .preview(let suggestion) = phase { return suggestion }
        return nil
    }

    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// "3 of 50 used today" — worth showing, because the spend is the user's own.
    var quotaSummary: String? {
        guard let quota = availability.quota, quota.dailyLimit > 0 else { return nil }
        return "\(quota.usedToday) of \(quota.dailyLimit) AI requests used today"
    }

    // MARK: - Availability

    /// Reads availability. Free — no quota, no provider call — so it is safe to
    /// call when the composer appears.
    func refreshAvailability() async {
        do {
            availability = try await ai.availability()
        } catch {
            // A failed read must not masquerade as "unavailable"; leaving the
            // previous value avoids flickering the menu off on a transient error.
            if !hasCheckedAvailability {
                availability = .unavailable
            }
        }
        hasCheckedAvailability = true
    }

    // MARK: - Running

    /// Runs a composer assistant action over the current draft.
    func assist(action: AIWritingAction, draft: String) async {
        await run(feature: .writingAssist) { [ai] in
            try await ai.assist(draft: draft, action: action)
        }
    }

    /// Plans a message series sized to the composer's cross-post selection.
    func planMessageSeries(brief: String, channels: [String]) async {
        await run(feature: .messageSeries) { [ai] in
            try await ai.planMessageSeries(brief: brief, channels: channels)
        }
    }

    /// Plans an article series.
    func planArticleSeries(brief: String) async {
        await run(feature: .articleSeries) { [ai] in
            try await ai.planArticleSeries(brief: brief)
        }
    }

    /// Drafts a list schema plus starter rows.
    func draftListTemplate(describing description: String) async {
        await run(feature: .listTemplate) { [ai] in
            try await ai.draftListTemplate(describing: description)
        }
    }

    /// Drafts a document.
    func draftDocument(prompt: String, mode: AIDocumentMode) async {
        await run(feature: .document) { [ai] in
            try await ai.draftDocument(prompt: prompt, mode: mode)
        }
    }

    // MARK: - Confirming

    /// Persists the pending preview. Only series and the generative features
    /// need this — an assistant rewrite is applied to the draft locally and
    /// never round-trips to `generate`.
    func confirmPending(crossPost: [String: Bool]? = nil, scheduleImmediately: Bool? = nil) async {
        guard let suggestion = pendingSuggestion else { return }
        phase = .confirming
        do {
            let result = try await ai.confirm(
                suggestion,
                crossPost: crossPost,
                scheduleImmediately: scheduleImmediately
            )
            phase = .finished(message: Self.message(for: result), result: result)
            // The confirm consumed nothing extra, but the suggest that produced
            // this artifact did — refresh so the quota line stays honest.
            await refreshAvailability()
        } catch {
            phase = .failed(message: Self.message(for: error))
        }
    }

    /// Discards any preview or error and returns to idle.
    func reset() {
        phase = .idle
    }

    // MARK: - Internals

    private func run(feature: AIFeature, _ body: @escaping () async throws -> AISuggestion) async {
        guard !isBusy else { return }
        phase = .running(feature)
        do {
            let suggestion = try await body()
            phase = .preview(suggestion)
            if let quota = suggestion.quota {
                // The response reports the post-call quota; adopt it rather than
                // waiting for the next availability read.
                availability = AIAvailability(
                    isSubscriber: availability.isSubscriber,
                    providers: availability.providers,
                    defaultModels: availability.defaultModels,
                    quota: quota
                )
            }
        } catch {
            phase = .failed(message: Self.message(for: error))
        }
    }

    /// User-facing text for a failure. `AIError` cases are phrased for a person;
    /// anything else falls back to the error's own description.
    static func message(for error: Error) -> String {
        switch error {
        case AIError.unavailable(let reason):
            return reason
        case AIError.inputTooShort(let minimum):
            return "Write at least \(minimum) word\(minimum == 1 ? "" : "s") before using AI."
        case AIError.quotaExhausted(let limit):
            return "You've used today's \(limit) AI requests. The limit resets tomorrow."
        case AIError.providerRejected(let message):
            return message ?? "The AI provider couldn't complete that request."
        default:
            return error.localizedDescription
        }
    }

    /// User-facing confirmation text for a generation result.
    static func message(for result: AIGenerationResult) -> String {
        switch result {
        case .list:
            return "List created."
        case .document:
            return "Document created."
        case .scheduledMessages(let ids, let firstScheduledAt):
            let count = "Scheduled \(ids.count) message\(ids.count == 1 ? "" : "s")"
            guard let firstScheduledAt else { return count + "." }
            let time = firstScheduledAt.formatted(date: .omitted, time: .shortened)
            return "\(count) — first around \(time)."
        case .created:
            return "Created."
        }
    }
}

// MARK: - Outcome

/// What the user chose to do with an assistant preview. The composer applies it;
/// the assistant view model has no business writing into the draft.
enum AIAssistantOutcome: Equatable {
    /// Replace the draft with rewritten prose.
    case replaceDraft(String)
    /// Append thread parts to the draft, joined the way the web app joins them.
    case useThread([String])
    /// Append suggested tags to the tag field.
    case addTags([String])
}
