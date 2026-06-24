import Foundation
import InterlinedKit

// MARK: - DTO → domain mapping (M4)
//
// One file owns every kit-DTO → domain-model translation for the Documents
// surface so the boundary is auditable in a single place (Decision 0003 —
// only domain knows about kit DTOs). Mappers are pure, total functions
// implemented as `init(from:)` so call sites read as plain conversions.

extension Document {

    /// Maps a `DocumentDTO`. The wire `content` is optional on the sync delta
    /// envelope and required on detail/create responses — the domain
    /// collapses both into a `DocumentBody`, defaulting to `.empty` when the
    /// field is absent. `updatedAt` is required for the domain to make any
    /// useful conflict decision, so when the wire omits it we fall back to
    /// `createdAt` (or `Date.distantPast` if both are absent — a defensive
    /// floor that loses to any real server timestamp).
    public init(from dto: DocumentDTO) {
        let updated = dto.updatedAt ?? dto.createdAt ?? Date.distantPast
        self.init(
            id: dto.id,
            folderId: dto.folderId,
            title: dto.title,
            body: DocumentBody(markdown: dto.content ?? ""),
            updatedAt: updated,
            createdAt: dto.createdAt,
            isPublic: dto.isPublic ?? false,
            deleted: dto.deleted ?? false,
            version: nil
        )
    }
}

extension FolderNode {

    /// Maps a `DocumentFolderDTO`. The wire `parentId` is optional; the
    /// domain projects it through unchanged. `deleted` defaults to `false`.
    public init(from dto: DocumentFolderDTO) {
        self.init(
            id: dto.id,
            parentId: dto.parentId,
            name: dto.name,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deleted: dto.deleted ?? false
        )
    }
}

// MARK: - DocumentChange → wire

extension DocumentSyncOperation {

    /// Projects a domain `DocumentChange` into the kit's
    /// `DocumentSyncOperation` wire shape. Used by the sync engine's outbox
    /// push leg. Inverse of the convention used by `ListJSONValue.init(from:)`
    /// in `ListsService`.
    public init(from change: DocumentChange) {
        switch change {
        case .createDocument(let id, let folderId, let title, let body, let isPublic):
            self.init(
                operation: "create",
                type: "document",
                id: id,
                title: title,
                content: body,
                name: nil,
                folderId: folderId,
                parentId: nil,
                relativePath: nil,
                isPublic: isPublic
            )

        case .updateDocument(let id, let title, let body, let folderId, let isPublic):
            self.init(
                operation: "update",
                type: "document",
                id: id,
                title: title,
                content: body,
                name: nil,
                folderId: folderId,
                parentId: nil,
                relativePath: nil,
                isPublic: isPublic
            )

        case .deleteDocument(let id):
            self.init(
                operation: "delete",
                type: "document",
                id: id
            )

        case .createFolder(let id, let name, let parentId):
            self.init(
                operation: "create",
                type: "folder",
                id: id,
                name: name,
                parentId: parentId
            )

        case .renameFolder(let id, let name, let parentId):
            self.init(
                operation: "update",
                type: "folder",
                id: id,
                name: name,
                parentId: parentId
            )

        case .deleteFolder(let id):
            self.init(
                operation: "delete",
                type: "folder",
                id: id
            )
        }
    }
}
