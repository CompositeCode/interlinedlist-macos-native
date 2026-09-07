import Foundation
import InterlinedKit

// MARK: - Availability

extension AIAvailability {

    /// Maps `GET /api/ai/status`. A server that omits `subscriber` is treated as
    /// **not** entitled — the safe direction, since the alternative offers a
    /// control that fails on use.
    public init(from dto: AIStatusDTO) {
        self.init(
            isSubscriber: dto.subscriber ?? false,
            providers: dto.providers ?? [],
            defaultModels: dto.defaultModels ?? [:],
            quota: dto.quota.map(AIQuota.init(from:))
        )
    }
}

extension AIQuota {

    public init(from dto: AIStatusDTO.QuotaDTO) {
        // `remaining` is reported but derivable; recompute it so a server that
        // sends an inconsistent trio cannot make `remaining` disagree with the
        // counters the UI shows.
        self.init(usedToday: dto.usedToday ?? 0, dailyLimit: dto.dailyLimit ?? 0)
    }
}

extension AIUsage {

    public init(from dto: AIUsageDTO) {
        self.init(inputTokens: dto.inputTokens, outputTokens: dto.outputTokens, model: dto.model)
    }
}

// MARK: - Suggestion

extension AISuggestion {

    /// Projects a suggest response. Returns `nil` when the body carried no
    /// artifact at all, so the caller can raise an error instead of presenting
    /// an empty preview sheet.
    public init?(from dto: AISuggestResponse, feature: AIFeature) {
        guard let artifact = dto.artifact else { return nil }
        self.init(
            feature: feature,
            artifact: AIArtifact(from: artifact, feature: feature),
            usage: dto.usage.map(AIUsage.init(from:)),
            quota: dto.quota.map(AIQuota.init(from:)),
            token: AIArtifactToken(dto: artifact)
        )
    }
}

extension AIArtifact {

    /// Projects the wire artifact.
    ///
    /// `kind` is authoritative where present — the live values are `message`,
    /// `tags`, `thread`, `message_series`, `list`, `document` — and the populated
    /// members are the fallback. The requesting feature is consulted last,
    /// because a server that renames a kind should still render if the payload
    /// is recognisable.
    public init(from dto: AIArtifactDTO, feature: AIFeature) {
        switch dto.kind {
        case "tags":
            self = .tags(dto.tags ?? [])
            return
        case "thread":
            self = .thread(parts: dto.parts ?? [])
            return
        case "message":
            self = .message(dto.content ?? "")
            return
        default:
            break
        }

        if let items = dto.items, !items.isEmpty {
            self = .messageSeries(
                listTitle: dto.listTitle,
                items: items.enumerated().map { index, item in
                    AISeriesItem(
                        order: item.order ?? index + 1,
                        content: item.content ?? "",
                        crossPostTargets: item.crossPostTargets ?? []
                    )
                }
            )
            return
        }

        if let documents = dto.documents, !documents.isEmpty {
            self = .articleSeries(documents: documents.map {
                AISeriesDocument(title: $0.title ?? "Untitled", markdown: $0.markdown)
            })
            return
        }

        if let dsl = dto.dsl {
            self = .listTemplate(AIListTemplateDraft(from: dto, dsl: dsl))
            return
        }

        if let markdown = dto.markdown {
            self = .document(AIDocumentDraft(
                title: dto.title ?? "Untitled",
                markdown: markdown,
                outline: dto.outline ?? [],
                isPublic: dto.isPublic ?? false
            ))
            return
        }

        // A rewrite that arrived without a recognised `kind` still has prose.
        if let content = dto.content, feature == .writingAssist {
            self = .message(content)
            return
        }

        self = .unknown(kind: dto.kind)
    }
}

extension AIListTemplateDraft {

    init(from dto: AIArtifactDTO, dsl: AIArtifactDTO.ListDSLDTO) {
        let fields = (dsl.fields ?? []).enumerated().map { index, field in
            AIListTemplateField(
                key: field.key ?? "field_\(index)",
                label: field.label ?? field.key ?? "Field \(index + 1)",
                type: field.type ?? "text",
                isRequired: field.required ?? false,
                displayOrder: field.displayOrder ?? index
            )
        }
        self.init(
            title: dto.title ?? dsl.name ?? "Untitled list",
            description: dto.description ?? dsl.description,
            fields: fields.sorted { $0.displayOrder < $1.displayOrder },
            rows: (dto.rows ?? []).map { row in
                row.reduce(into: [String: String]()) { result, pair in
                    result[pair.key] = pair.value.displayString
                }
            }
        )
    }
}

// MARK: - Generation result

extension AIGenerationResult {

    /// Maps `POST /api/ai/generate`. Order matters: a scheduled series can report
    /// message ids *and* a list id, and the scheduling is the outcome the user
    /// actually asked for.
    public init(from dto: AIGenerateResponse) {
        guard let created = dto.created else {
            self = .created
            return
        }
        if let ids = created.scheduledMessageIds, !ids.isEmpty {
            self = .scheduledMessages(ids: ids, firstScheduledAt: created.firstScheduledAt)
        } else if let listId = created.listId {
            self = .list(id: listId)
        } else if let documentId = created.documentId {
            self = .document(id: documentId)
        } else {
            self = .created
        }
    }
}

// MARK: - JSON value rendering

private extension AIJSONValue {

    /// Renders a starter-row cell for display. Only the preview uses this — the
    /// confirm step echoes the server's own artifact back, so nothing depends on
    /// a lossless round-trip here.
    var displayString: String {
        switch self {
        case .null: return ""
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return value
        case .array(let values): return values.map(\.displayString).joined(separator: ", ")
        case .object(let values):
            return values
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.displayString)" }
                .joined(separator: ", ")
        }
    }
}
