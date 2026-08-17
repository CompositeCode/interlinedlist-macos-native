import Foundation

// MARK: - Server document-template DTOs (work-consolidation.md G12)
//
// The user's own saved template documents (distinct from the client-side
// built-in catalog). Shapes verified live 2026-07-31:
//
//   GET  /api/documents/templates
//        -> { folderCreated: Bool, templatesFolderId: String,
//             templates: [{ id, title, relativePath }] }
//   POST /api/documents/from-template { templateDocumentId }  -> 201 (empty body)
//   POST /api/documents/templates/seed-defaults               -> seeds defaults

/// A reference to one server-side template document.
public struct DocumentTemplateDTO: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let relativePath: String?

    public init(id: String, title: String, relativePath: String? = nil) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
    }
}

/// `GET /api/documents/templates` response. Ensures the `_templates` folder
/// exists (`folderCreated` is `true` the first time) and lists the templates.
public struct DocumentTemplatesResponse: Decodable, Sendable, Equatable {
    public let folderCreated: Bool?
    public let templatesFolderId: String?
    public let templates: [DocumentTemplateDTO]

    public init(folderCreated: Bool? = nil, templatesFolderId: String? = nil, templates: [DocumentTemplateDTO]) {
        self.folderCreated = folderCreated
        self.templatesFolderId = templatesFolderId
        self.templates = templates
    }
}

/// Body for `POST /api/documents/from-template`. The field name is
/// `templateDocumentId` (verified live — a bare `templateId` returns
/// `400 "templateDocumentId is required."`).
public struct CreateFromTemplateRequest: Encodable, Sendable, Equatable {
    public let templateDocumentId: String

    public init(templateDocumentId: String) {
        self.templateDocumentId = templateDocumentId
    }
}
