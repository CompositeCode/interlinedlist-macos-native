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

// MARK: - Sidebar tree (work-consolidation.md G24)

extension FolderNode {

    /// Maps a `DocumentTreeFolderDTO`. The tree's folder rows are thinner than
    /// `DocumentFolderDTO`: no `createdAt` / `updatedAt` and no `deleted`
    /// tombstone (the tree only ever returns live folders). Those project to
    /// `nil` / `false` rather than being invented.
    public init(from dto: DocumentTreeFolderDTO) {
        self.init(
            id: dto.id,
            parentId: dto.parentId,
            name: dto.name,
            createdAt: nil,
            updatedAt: nil,
            deleted: false
        )
    }
}

extension DocumentSummary {

    /// Maps a document row from the tree or the public-by-user route.
    ///
    /// `folderID` is passed in rather than read off the DTO because the tree
    /// nests documents under their folder and omits `folderId` entirely; the
    /// caller supplies the enclosing folder (or `nil` for `rootDocuments`).
    /// When the DTO *does* carry a `folderId` (the public-by-user route), that
    /// value wins — the caller has no better information there.
    public init(from dto: DocumentDTO, folderID: FolderNode.ID?) {
        self.init(
            id: dto.id,
            title: dto.title,
            folderId: dto.folderId ?? folderID,
            relativePath: dto.relativePath,
            isPublic: dto.isPublic ?? false
        )
    }
}

extension DocumentTreeSnapshot {

    /// Maps `GET /api/documents/tree` into the sidebar snapshot.
    ///
    /// Root documents stay a separate array — flattening them into a synthetic
    /// folder would erase the "no folder" destination the move action needs.
    /// `_templates` is kept in `folders` (the picker looks it up by name) and
    /// filtered out of the user-facing projections on the snapshot itself.
    public init(from dto: DocumentTreeResponse) {
        var index: [FolderNode.ID: [DocumentSummary]] = [:]
        for folder in dto.folders {
            index[folder.id] = folder.documents.map {
                DocumentSummary(from: $0, folderID: folder.id)
            }
        }
        self.init(
            folders: dto.folders.map(FolderNode.init(from:)),
            documentsByFolder: index,
            rootDocuments: dto.rootDocuments.map {
                DocumentSummary(from: $0, folderID: nil)
            }
        )
    }
}

// MARK: - Public documents by user (work-consolidation.md G24)

extension PublicUserDocuments {

    /// Maps `GET /api/users/{username}/documents`. The username is not in the
    /// response body — it is the path parameter — so the caller passes it back
    /// in for display.
    public init(username: String, from dto: PublicUserDocumentsResponse) {
        self.init(
            username: username,
            documents: dto.documents.map(Document.init(from:)),
            folders: dto.folders.map(FolderNode.init(from:))
        )
    }
}

// MARK: - Invite landing (work-consolidation.md G24)

extension DocumentInvite {

    /// Maps `GET /api/documents/invite/{token}`. Every branch flag is optional
    /// on the wire and collapses to `false` here: an absent flag means "this
    /// branch does not apply", which is exactly what `false` renders as.
    ///
    /// The token is not echoed in the body, so it is threaded through from the
    /// request — the landing view needs it to build the browser hand-off URL.
    public init(token: String, from dto: DocumentInviteLandingDTO) {
        self.init(
            token: token,
            role: dto.role,
            resourceTitle: dto.resourceTitle,
            needsAuth: dto.needsAuth ?? false,
            canClaim: dto.canClaim ?? false,
            wrongAccount: dto.wrongAccount ?? false,
            accepted: dto.accepted ?? false
        )
    }
}
