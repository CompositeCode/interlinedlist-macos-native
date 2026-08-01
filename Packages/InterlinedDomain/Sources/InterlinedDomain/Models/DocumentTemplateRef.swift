import Foundation
import InterlinedKit

/// A reference to one of the user's **server-side** template documents
/// (the-gaps.md G12). Distinct from `DocumentTemplate`, which is the app's
/// built-in, client-side starter catalog (Blank / Meeting Notes / …). Server
/// templates are the user's own saved documents in the `_templates` folder and
/// sync across devices.
public struct DocumentTemplateRef: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let relativePath: String?

    public init(id: String, title: String, relativePath: String? = nil) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
    }
}

extension DocumentTemplateRef {
    public init(from dto: DocumentTemplateDTO) {
        self.init(id: dto.id, title: dto.title, relativePath: dto.relativePath)
    }
}
