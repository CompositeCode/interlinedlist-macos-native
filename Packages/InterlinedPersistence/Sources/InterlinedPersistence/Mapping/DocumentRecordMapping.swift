import Foundation
import InterlinedDomain

/// Internal mapping between SwiftData document records and the domain value
/// types. Mirrors the `MessageRecordMapping` / `ListRecordMapping` pattern:
/// callers consume `Document` / `FolderNode` values across the actor
/// boundary and never see `@Model` types directly.

// MARK: - DocumentRecord ↔ Document

extension DocumentRecord {

    convenience init(from document: Document, localEditedAt: Date? = nil) {
        self.init(
            id: document.id,
            folderId: document.folderId,
            title: document.title,
            bodyMarkdown: document.body.markdown,
            updatedAt: document.updatedAt,
            createdAt: document.createdAt,
            isPublic: document.isPublic,
            deleted: document.deleted,
            version: document.version,
            localEditedAt: localEditedAt
        )
    }

    /// Overlay every mutable field from a fresh `Document`. Does NOT touch
    /// `localEditedAt` — callers manage the dirty flag explicitly.
    func apply(_ document: Document) {
        folderId = document.folderId
        title = document.title
        bodyMarkdown = document.body.markdown
        updatedAt = document.updatedAt
        createdAt = document.createdAt
        isPublic = document.isPublic
        deleted = document.deleted
        version = document.version
    }

    func toDocument() -> Document {
        Document(
            id: id,
            folderId: folderId,
            title: title,
            body: DocumentBody(markdown: bodyMarkdown),
            updatedAt: updatedAt,
            createdAt: createdAt,
            isPublic: isPublic,
            deleted: deleted,
            version: version
        )
    }
}

// MARK: - FolderRecord ↔ FolderNode

extension FolderRecord {

    convenience init(from folder: FolderNode) {
        self.init(
            id: folder.id,
            parentId: folder.parentId,
            name: folder.name,
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt,
            deleted: folder.deleted
        )
    }

    func apply(_ folder: FolderNode) {
        parentId = folder.parentId
        name = folder.name
        createdAt = folder.createdAt
        updatedAt = folder.updatedAt
        deleted = folder.deleted
    }

    func toFolderNode() -> FolderNode {
        FolderNode(
            id: id,
            parentId: parentId,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deleted: deleted
        )
    }
}
