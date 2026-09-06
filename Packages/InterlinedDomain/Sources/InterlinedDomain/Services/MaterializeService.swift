import Foundation
import InterlinedKit

// MARK: - MaterializeServicing

/// "Create from…" (work-consolidation.md G16) — turn messages, lists, rows, a
/// document, or a highlighted selection into a new list, a new document, or both.
///
/// One call, one creation: the server does the extraction, so there is no
/// preview round-trip like the AI pair has. The App layer previews locally from
/// content it already holds.
public protocol MaterializeServicing: Sendable {
    func create(_ spec: MaterializeSpec) async throws -> MaterializeOutcome
}

// MARK: - MaterializeService

public final class MaterializeService: MaterializeServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func create(_ spec: MaterializeSpec) async throws -> MaterializeOutcome {
        // Refuse locally what the server would refuse anyway. Its rejections are
        // unusually unhelpful here — a wrong column shape reports a missing `key`
        // property even when one is present — so a client-side gate keeps users
        // out of a message that cannot be acted on.
        guard spec.isComplete else {
            throw MaterializeError.incompleteSpec
        }

        let response = try await api.send(Materialize.create(MaterializeRequest(
            target: spec.output.wireTarget,
            source: spec.source.wireSource,
            listConfig: spec.list.map {
                MaterializeListConfig(
                    title: $0.title.trimmed,
                    description: $0.description?.trimmed.nilIfEmpty,
                    isPublic: $0.isPublic,
                    fields: $0.columns.map(\.wireField),
                    includeData: $0.includeSourceData
                )
            },
            docConfig: spec.document.map {
                MaterializeDocConfig(
                    title: $0.title.trimmed,
                    relativePath: $0.folderPath?.trimmed.nilIfEmpty,
                    isPublic: $0.isPublic,
                    listStyle: $0.listStyle.wireStyle,
                    rowDataStyle: $0.rowDataStyle.wireStyle
                )
            }
        )))

        return MaterializeOutcome(from: response)
    }
}

// MARK: - Errors

public enum MaterializeError: Error, Sendable, Equatable {
    /// A required title or column set is missing. Presented as a disabled Create
    /// button rather than a thrown error in normal use.
    case incompleteSpec
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
