import Foundation

/// Server document-template builders (work-consolidation.md G12), added to the existing
/// `Documents` namespace as an additive extension so the base endpoint file is
/// untouched. Verified live 2026-07-31.
public extension Documents {

    /// `GET /api/documents/templates` — the user's saved template documents
    /// (ensures the `_templates` folder exists).
    static func templates() -> Request<DocumentTemplatesResponse> {
        Request(method: .get, path: "/api/documents/templates", auth: .bearer)
    }

    /// `POST /api/documents/from-template` — create a new document by copying
    /// the given template. Returns 201 with an empty body; callers reload the
    /// documents list to surface the new document.
    static func createFromTemplate(_ body: CreateFromTemplateRequest) -> Request<EmptyResponse> {
        Request(method: .post, path: "/api/documents/from-template", body: .json(body), auth: .bearer)
    }

    /// `POST /api/documents/templates/seed-defaults` — seed the default
    /// starter templates into the `_templates` folder.
    static func seedDefaultTemplates() -> Request<EmptyResponse> {
        Request(method: .post, path: "/api/documents/templates/seed-defaults", auth: .bearer)
    }
}
