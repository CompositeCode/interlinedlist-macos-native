import Foundation

// MARK: - Status

/// `GET /api/ai/status` response (work-consolidation.md G15).
///
/// Shape captured live 2026-09-05 against the `.env` test account:
///
/// ```json
/// { "subscriber": true,
///   "providers": ["anthropic"],
///   "defaultModels": { "anthropic": "claude-sonnet-5", "openai": "gpt-4.1-mini",
///                      "gemini": "gemini-2.0-flash" },
///   "quota": { "usedToday": 0, "dailyLimit": 50, "remaining": 50 } }
/// ```
///
/// AI is subscriber-gated **and** requires the account to have supplied its own
/// provider key on the web Integrations page, so `providers` can be empty for a
/// subscriber who has not configured one. Every field is optional so a server
/// that adds or renames one still decodes.
public struct AIStatusDTO: Decodable, Sendable, Equatable {
    public let subscriber: Bool?
    public let providers: [String]?
    public let defaultModels: [String: String]?
    public let quota: QuotaDTO?

    public init(
        subscriber: Bool? = nil,
        providers: [String]? = nil,
        defaultModels: [String: String]? = nil,
        quota: QuotaDTO? = nil
    ) {
        self.subscriber = subscriber
        self.providers = providers
        self.defaultModels = defaultModels
        self.quota = quota
    }

    public struct QuotaDTO: Decodable, Sendable, Equatable {
        public let usedToday: Int?
        public let dailyLimit: Int?
        public let remaining: Int?

        public init(usedToday: Int? = nil, dailyLimit: Int? = nil, remaining: Int? = nil) {
            self.usedToday = usedToday
            self.dailyLimit = dailyLimit
            self.remaining = remaining
        }
    }
}

// MARK: - Feature + context

/// The five AI features the live route accepts. Enumerated 2026-09-05 by
/// probing `POST /api/ai/suggest` with `{"feature": …}` and no `input`: a valid
/// feature answers `422 {"error":"Input is required."}` while anything else
/// answers `422 {"error":"Unknown or missing feature."}`. No AI call is made on
/// either path, so the enum was mapped without spending the account's quota.
public enum AIFeature: String, Sendable, Equatable, CaseIterable, Codable {
    /// Composer writing assistant — see `AIWritingAction`.
    case writingAssist = "writing_assist"
    /// A brief → a sequence of connected short posts.
    case messageSeries = "message_series"
    /// A brief → a sequence of connected documents.
    case articleSeries = "article_series"
    /// A drafted list schema + starter rows ("AI powered templates").
    case poweredTemplate = "powered_template"
    /// A drafted document — see `AIDocumentMode`.
    case poweredDocument = "powered_document"
}

/// `context.action` values for `AIFeature.writingAssist`, with the labels the
/// web composer shows. Captured from the web client's own menu table.
public enum AIWritingAction: String, Sendable, Equatable, CaseIterable, Codable {
    case rewrite
    case tighten
    case expand
    case grammar
    case thread
    case tags

    /// The label the web composer uses, mirrored so the native menu reads the same.
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
}

/// `context.mode` values for `AIFeature.poweredDocument`.
public enum AIDocumentMode: String, Sendable, Equatable, CaseIterable, Codable {
    /// Standalone article from a topic description. No extra context field.
    case article
    /// Derived from one of the caller's lists — carries `listId`.
    case fromList = "from_list"
    /// Derived from an existing document — carries `documentId`.
    case fromArticle = "from_article"
    /// Researched from a web page — carries `url`.
    case researchURL = "research_url"
}

/// The `context` object on a suggest request. Which members are populated
/// depends on the feature; all are optional and nil members are omitted, which
/// matches how the web client builds the same object.
public struct AISuggestContext: Encodable, Sendable, Equatable {
    public let action: AIWritingAction?
    public let mode: AIDocumentMode?
    public let listId: String?
    public let documentId: String?
    public let url: String?
    /// Cross-post destinations for `messageSeries`, e.g. `["Bluesky", "Mastodon"]`.
    /// The server sizes each part to the smallest selected platform's limit.
    public let channels: [String]?

    public init(
        action: AIWritingAction? = nil,
        mode: AIDocumentMode? = nil,
        listId: String? = nil,
        documentId: String? = nil,
        url: String? = nil,
        channels: [String]? = nil
    ) {
        self.action = action
        self.mode = mode
        self.listId = listId
        self.documentId = documentId
        self.url = url
        self.channels = channels
    }

    /// Convenience for the composer assistant.
    public static func writing(_ action: AIWritingAction) -> AISuggestContext {
        AISuggestContext(action: action)
    }

    /// Convenience for a message series sized to the given cross-post channels.
    public static func series(channels: [String]) -> AISuggestContext {
        AISuggestContext(channels: channels)
    }
}

// MARK: - Suggest

/// `POST /api/ai/suggest` request body — `{ feature, input, context? }`.
public struct AISuggestRequest: Encodable, Sendable, Equatable {
    public let feature: AIFeature
    public let input: String
    public let context: AISuggestContext?

    public init(feature: AIFeature, input: String, context: AISuggestContext? = nil) {
        self.feature = feature
        self.input = input
        self.context = context
    }
}

/// `POST /api/ai/suggest` response — `{ artifact }`. The artifact is a preview:
/// nothing is persisted until the same artifact is posted back to
/// `POST /api/ai/generate`.
public struct AISuggestResponse: Decodable, Sendable, Equatable {
    public let artifact: AIArtifactDTO?

    public init(artifact: AIArtifactDTO? = nil) {
        self.artifact = artifact
    }
}

/// The polymorphic preview artifact. One decoder covers every feature because
/// the server discriminates by `kind` only for `writingAssist`; the other
/// features return their own top-level members. Every field is optional and the
/// raw JSON is retained so an artifact can be replayed to `/api/ai/generate`
/// byte-for-byte even if this client does not model one of its members.
///
/// Per feature (captured from the web client's rendering code):
/// - `writingAssist` → `kind: "text"` + `content`, `kind: "thread"` + `parts`,
///   or `kind: "tags"` + `tags`.
/// - `messageSeries` → `items[].content`.
/// - `articleSeries` → `documents[].title`.
/// - `poweredDocument` → `title`, `outline`, `markdown`.
/// - `poweredTemplate` → **unverified**; the members below are the modelled
///   guess and unknown members survive in `raw`.
public struct AIArtifactDTO: Codable, Sendable, Equatable {
    public let kind: String?
    public let content: String?
    public let parts: [String]?
    public let tags: [String]?
    public let items: [SeriesItemDTO]?
    public let documents: [SeriesDocumentDTO]?
    public let title: String?
    public let outline: [String]?
    public let markdown: String?
    /// The artifact exactly as the server sent it, so `generate` can echo it back
    /// without lossy round-tripping through the modelled members.
    public let raw: AIJSONValue?

    public struct SeriesItemDTO: Codable, Sendable, Equatable {
        public let content: String?
        public init(content: String? = nil) { self.content = content }
    }

    public struct SeriesDocumentDTO: Codable, Sendable, Equatable {
        public let title: String?
        public let markdown: String?
        public init(title: String? = nil, markdown: String? = nil) {
            self.title = title
            self.markdown = markdown
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, content, parts, tags, items, documents, title, outline, markdown
    }

    public init(
        kind: String? = nil,
        content: String? = nil,
        parts: [String]? = nil,
        tags: [String]? = nil,
        items: [SeriesItemDTO]? = nil,
        documents: [SeriesDocumentDTO]? = nil,
        title: String? = nil,
        outline: [String]? = nil,
        markdown: String? = nil,
        raw: AIJSONValue? = nil
    ) {
        self.kind = kind
        self.content = content
        self.parts = parts
        self.tags = tags
        self.items = items
        self.documents = documents
        self.title = title
        self.outline = outline
        self.markdown = markdown
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        parts = try c.decodeIfPresent([String].self, forKey: .parts)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        items = try c.decodeIfPresent([SeriesItemDTO].self, forKey: .items)
        documents = try c.decodeIfPresent([SeriesDocumentDTO].self, forKey: .documents)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        outline = try c.decodeIfPresent([String].self, forKey: .outline)
        markdown = try c.decodeIfPresent(String.self, forKey: .markdown)
        // Capture the whole object so `generate` can echo it verbatim.
        raw = try? AIJSONValue(from: decoder)
    }

    /// Encodes `raw` when present so a round-trip to `/api/ai/generate` carries
    /// every member the server sent, modelled or not.
    public func encode(to encoder: Encoder) throws {
        if let raw {
            try raw.encode(to: encoder)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(parts, forKey: .parts)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(items, forKey: .items)
        try c.encodeIfPresent(documents, forKey: .documents)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(outline, forKey: .outline)
        try c.encodeIfPresent(markdown, forKey: .markdown)
    }
}

// MARK: - Generate

/// `POST /api/ai/generate` request body — `{ feature, artifact }`, plus the two
/// `messageSeries`-only members the web client adds (`crossPost`,
/// `scheduleImmediately`). `generate` is the **persisting** half of the pair.
public struct AIGenerateRequest: Encodable, Sendable, Equatable {
    public let feature: AIFeature
    public let artifact: AIArtifactDTO
    /// Cross-post destination flags, echoed from the composer's own selection.
    public let crossPost: [String: Bool]?
    /// `messageSeries` only: post the series on a schedule instead of creating a list.
    public let scheduleImmediately: Bool?

    public init(
        feature: AIFeature,
        artifact: AIArtifactDTO,
        crossPost: [String: Bool]? = nil,
        scheduleImmediately: Bool? = nil
    ) {
        self.feature = feature
        self.artifact = artifact
        self.crossPost = crossPost
        self.scheduleImmediately = scheduleImmediately
    }
}

/// `POST /api/ai/generate` response — `{ created: … }`. Which members are
/// populated depends on the feature: a scheduled message series returns
/// `scheduledMessageIds` + `firstScheduledAt`, an unscheduled one returns
/// `listId`, and a powered document returns `documentId`.
public struct AIGenerateResponse: Decodable, Sendable, Equatable {
    public let created: CreatedDTO?

    public init(created: CreatedDTO? = nil) { self.created = created }

    public struct CreatedDTO: Decodable, Sendable, Equatable {
        public let listId: String?
        public let documentId: String?
        public let scheduledMessageIds: [String]?
        public let firstScheduledAt: String?

        public init(
            listId: String? = nil,
            documentId: String? = nil,
            scheduledMessageIds: [String]? = nil,
            firstScheduledAt: String? = nil
        ) {
            self.listId = listId
            self.documentId = documentId
            self.scheduledMessageIds = scheduledMessageIds
            self.firstScheduledAt = firstScheduledAt
        }
    }
}

// MARK: - AIJSONValue

/// A minimal type-erased JSON value, used so `AIArtifactDTO` can carry the
/// server's artifact **verbatim** and echo it back to `POST /api/ai/generate`.
///
/// The kit already has an internal `JSONValue` for pagination splitting, but it
/// is deliberately not public; this is the public counterpart scoped to the AI
/// DTOs, so the artifact round-trip never depends on this client having modelled
/// every member the server invented.
public enum AIJSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AIJSONValue])
    case object([String: AIJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([AIJSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: AIJSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}
