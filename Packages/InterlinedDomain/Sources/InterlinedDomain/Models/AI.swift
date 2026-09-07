import Foundation
import InterlinedKit

// MARK: - Features

/// The AI features the platform offers (work-consolidation.md G15). Mirrors the
/// kit's wire enum so the App layer never imports `InterlinedKit` (decision 0003).
public enum AIFeature: String, Sendable, Equatable, CaseIterable, Identifiable {
    case writingAssist
    case messageSeries
    case articleSeries
    case listTemplate
    case document

    public var id: String { rawValue }

    /// The label the web app uses for the same feature, so the two clients read alike.
    public var title: String {
        switch self {
        case .writingAssist: return "Writing Assistant"
        case .messageSeries: return "Message Series"
        case .articleSeries: return "Article Series"
        case .listTemplate:  return "AI List Template"
        case .document:      return "AI Document"
        }
    }

    /// Minimum word count the web app requires before it will call. Enforced
    /// client-side so an obviously-too-short draft never spends a quota unit.
    public var minimumWords: Int {
        switch self {
        case .writingAssist: return 2
        case .messageSeries, .articleSeries: return 10
        case .listTemplate, .document: return 1
        }
    }

    var wireFeature: AIWireFeature {
        switch self {
        case .writingAssist: return .writingAssist
        case .messageSeries: return .messageSeries
        case .articleSeries: return .articleSeries
        case .listTemplate:  return .poweredTemplate
        case .document:      return .poweredDocument
        }
    }
}

/// What the composer assistant should do with the current draft.
public enum AIWritingAction: String, Sendable, Equatable, CaseIterable, Identifiable {
    case rewrite, tighten, expand, grammar, thread, tags

    public var id: String { rawValue }

    /// Menu label, matching the web composer's own wording.
    public var label: String {
        switch self {
        case .rewrite: return "Rewrite"
        case .tighten: return "Tighten to fit"
        case .expand:  return "Expand"
        case .grammar: return "Fix grammar"
        case .thread:  return "Split into thread"
        case .tags:    return "Suggest tags"
        }
    }

    var wireAction: AIWireWritingAction {
        switch self {
        case .rewrite: return .rewrite
        case .tighten: return .tighten
        case .expand:  return .expand
        case .grammar: return .grammar
        case .thread:  return .thread
        case .tags:    return .tags
        }
    }
}

/// Where an AI document is derived from.
public enum AIDocumentMode: Sendable, Equatable {
    /// A standalone article from a topic description.
    case article
    /// Derived from one of the caller's lists.
    case fromList(listId: String)
    /// Derived from an existing document.
    case fromArticle(documentId: String)
    /// Researched from a web page.
    case researchURL(URL)

    var wireContext: AISuggestContext {
        switch self {
        case .article:
            return AISuggestContext(mode: .article)
        case .fromList(let listId):
            return AISuggestContext(mode: .fromList, listId: listId)
        case .fromArticle(let documentId):
            return AISuggestContext(mode: .fromArticle, documentId: documentId)
        case .researchURL(let url):
            return AISuggestContext(mode: .researchURL, url: url.absoluteString)
        }
    }
}

// MARK: - Availability

/// Whether AI can be used right now, and if not, why. AI is gated on **two**
/// things the server owns: an active subscription and a provider key the user
/// supplied on the web Integrations page. Asking the server beats guessing from
/// `customerStatus`, because a paying user with no key still cannot call.
public struct AIAvailability: Sendable, Equatable {
    public let isSubscriber: Bool
    /// Provider slugs the account has configured, e.g. `["anthropic"]`.
    public let providers: [String]
    /// Default model per provider, as the server reports it.
    public let defaultModels: [String: String]
    public let quota: AIQuota?

    public init(
        isSubscriber: Bool,
        providers: [String] = [],
        defaultModels: [String: String] = [:],
        quota: AIQuota? = nil
    ) {
        self.isSubscriber = isSubscriber
        self.providers = providers
        self.defaultModels = defaultModels
        self.quota = quota
    }

    /// A safe default for a signed-out or unknown state: nothing is offered.
    public static let unavailable = AIAvailability(isSubscriber: false)

    public var isAvailable: Bool {
        isSubscriber && !providers.isEmpty && (quota?.hasRemaining ?? true)
    }

    /// A sentence the UI can show instead of a disabled control with no reason.
    public var unavailableReason: String? {
        if !isSubscriber {
            return "AI features are part of a subscription."
        }
        if providers.isEmpty {
            return "Add your own AI provider key in Settings on interlinedlist.com to use AI features."
        }
        if let quota, !quota.hasRemaining {
            return "You've used today's \(quota.dailyLimit) AI requests. The limit resets tomorrow."
        }
        return nil
    }
}

/// Daily AI request allowance.
public struct AIQuota: Sendable, Equatable {
    public let usedToday: Int
    public let dailyLimit: Int

    public init(usedToday: Int, dailyLimit: Int) {
        self.usedToday = usedToday
        self.dailyLimit = dailyLimit
    }

    public var remaining: Int { max(0, dailyLimit - usedToday) }
    public var hasRemaining: Bool { dailyLimit <= 0 || remaining > 0 }
}

/// Token spend and model for one AI call. Shown next to a preview so the cost of
/// the user's own provider key is visible rather than hidden.
public struct AIUsage: Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let model: String?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, model: String? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.model = model
    }
}

// MARK: - Artifacts

/// A previewed AI result, before the user confirms it.
///
/// `generate` must echo the server's artifact back **verbatim**, so the raw
/// payload travels with the projection as an opaque `token`. The App layer holds
/// the token and hands it back on confirm; it never needs to see inside it,
/// which keeps `InterlinedKit` out of the App target (decision 0003).
public struct AISuggestion: Sendable, Equatable {
    public let feature: AIFeature
    public let artifact: AIArtifact
    public let usage: AIUsage?
    public let quota: AIQuota?
    public let token: AIArtifactToken

    public init(
        feature: AIFeature,
        artifact: AIArtifact,
        usage: AIUsage? = nil,
        quota: AIQuota? = nil,
        token: AIArtifactToken
    ) {
        self.feature = feature
        self.artifact = artifact
        self.usage = usage
        self.quota = quota
        self.token = token
    }
}

/// The server's artifact, carried opaquely so it can be echoed back unchanged.
public struct AIArtifactToken: Sendable, Equatable {
    let dto: AIArtifactDTO

    init(dto: AIArtifactDTO) { self.dto = dto }

    /// An empty token for SwiftUI previews and App-layer tests, which cannot
    /// build a real one — the payload it wraps is a kit type, and the App target
    /// does not import the kit (decision 0003).
    ///
    /// **Never confirm one of these against the live service.** It would post an
    /// empty artifact to `/api/ai/generate`. It exists so a preview or a test can
    /// hold an `AISuggestion` without a network round-trip.
    public static let placeholder = AIArtifactToken(dto: AIArtifactDTO())
}

/// What an AI preview actually contains, projected per feature.
///
/// `.unknown` is deliberate: a server that adds a feature or renames a `kind`
/// should surface as "this preview can't be shown" rather than as a crash or a
/// silently empty sheet — and the token still round-trips, so a future client
/// can confirm it.
public enum AIArtifact: Sendable, Equatable {
    /// Rewritten / tightened / expanded / grammar-fixed prose. Server `kind: "message"`.
    case message(String)
    /// A draft split into thread parts.
    case thread(parts: [String])
    /// Suggested tags, without the leading `#`.
    case tags([String])
    /// A planned sequence of short posts.
    case messageSeries(listTitle: String?, items: [AISeriesItem])
    /// A planned sequence of documents.
    case articleSeries(documents: [AISeriesDocument])
    /// A drafted list schema plus starter rows.
    case listTemplate(AIListTemplateDraft)
    /// A drafted document.
    case document(AIDocumentDraft)
    /// A shape this client does not model.
    case unknown(kind: String?)
}

/// One post in a planned message series.
public struct AISeriesItem: Sendable, Equatable, Identifiable {
    public let order: Int
    public let content: String
    public let crossPostTargets: [String]

    public var id: Int { order }

    public init(order: Int, content: String, crossPostTargets: [String] = []) {
        self.order = order
        self.content = content
        self.crossPostTargets = crossPostTargets
    }
}

/// One document in a planned article series.
public struct AISeriesDocument: Sendable, Equatable, Identifiable {
    public let title: String
    public let markdown: String?

    public var id: String { title }

    public init(title: String, markdown: String? = nil) {
        self.title = title
        self.markdown = markdown
    }
}

/// A drafted list: the schema plus starter rows.
public struct AIListTemplateDraft: Sendable, Equatable {
    public let title: String
    public let description: String?
    public let fields: [AIListTemplateField]
    /// Starter rows, each keyed by the field keys above. Values are rendered as
    /// display strings; the confirm step sends the server's own artifact back,
    /// so nothing depends on this projection round-tripping.
    public let rows: [[String: String]]

    public init(
        title: String,
        description: String? = nil,
        fields: [AIListTemplateField],
        rows: [[String: String]] = []
    ) {
        self.title = title
        self.description = description
        self.fields = fields
        self.rows = rows
    }
}

/// One column of a drafted list schema.
public struct AIListTemplateField: Sendable, Equatable, Identifiable {
    public let key: String
    public let label: String
    public let type: String
    public let isRequired: Bool
    public let displayOrder: Int

    public var id: String { key }

    public init(key: String, label: String, type: String, isRequired: Bool = false, displayOrder: Int = 0) {
        self.key = key
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.displayOrder = displayOrder
    }
}

/// A drafted document.
public struct AIDocumentDraft: Sendable, Equatable {
    public let title: String
    public let markdown: String
    public let outline: [String]
    public let isPublic: Bool

    public init(title: String, markdown: String, outline: [String] = [], isPublic: Bool = false) {
        self.title = title
        self.markdown = markdown
        self.outline = outline
        self.isPublic = isPublic
    }
}

// MARK: - Generation result

/// What a confirmed artifact produced.
public enum AIGenerationResult: Sendable, Equatable {
    case list(id: String)
    case document(id: String)
    /// A message series posted on a schedule.
    case scheduledMessages(ids: [String], firstScheduledAt: Date?)
    /// The server reported success without an id this client recognises.
    case created
}

// MARK: - Errors

/// Failures the AI surface can present meaningfully. Anything else propagates as
/// the underlying `APIError`.
public enum AIError: Error, Sendable, Equatable {
    /// The account is not a subscriber, or has no provider key configured.
    case unavailable(reason: String)
    /// The draft is shorter than the feature's minimum.
    case inputTooShort(minimumWords: Int)
    /// The AI provider itself refused the request (live `502 provider_error`).
    case providerRejected(message: String?)
    /// Today's quota is spent.
    case quotaExhausted(dailyLimit: Int)
}
