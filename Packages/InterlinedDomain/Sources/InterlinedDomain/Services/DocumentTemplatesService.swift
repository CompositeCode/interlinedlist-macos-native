import Foundation
import InterlinedKit

// MARK: - DocumentTemplatesServicing

/// The server document-templates surface (the-gaps.md G12) — list the user's
/// saved templates, create a document from one, and seed the default starter
/// set. Kept as its own small service (rather than extending `DocumentsService`)
/// so no existing `DocumentsServicing` conformance changes.
///
/// `createFromTemplate` returns `Void`: the endpoint replies `201` with an empty
/// body, so the App layer reloads the documents list to surface the new document.
public protocol DocumentTemplatesServicing: Sendable {
    func templates() async throws -> [DocumentTemplateRef]
    func createFromTemplate(templateDocumentId: String) async throws
    func seedDefaultTemplates() async throws
}

// MARK: - DocumentTemplatesService

public final class DocumentTemplatesService: DocumentTemplatesServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func templates() async throws -> [DocumentTemplateRef] {
        let dto = try await api.send(Documents.templates())
        return dto.templates.map(DocumentTemplateRef.init(from:))
    }

    public func createFromTemplate(templateDocumentId: String) async throws {
        try await api.sendVoid(
            Documents.createFromTemplate(CreateFromTemplateRequest(templateDocumentId: templateDocumentId))
        )
    }

    public func seedDefaultTemplates() async throws {
        try await api.sendVoid(Documents.seedDefaultTemplates())
    }
}
