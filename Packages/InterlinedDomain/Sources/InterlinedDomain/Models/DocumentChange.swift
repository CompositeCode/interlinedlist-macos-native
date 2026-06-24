import Foundation

// MARK: - DocumentChange

/// A queued local edit the sync engine will push to the server on the next
/// `syncNow()` cycle. Mirrors `DocumentSyncOperation` (kit DTO) one-to-one
/// but stays in the domain so the App layer never imports the kit (Decision
/// 0003).
public enum DocumentChange: Sendable, Equatable {
    case createDocument(
        id: String,
        folderId: String?,
        title: String,
        body: String,
        isPublic: Bool
    )
    case updateDocument(
        id: String,
        title: String?,
        body: String?,
        folderId: String?,
        isPublic: Bool?
    )
    case deleteDocument(id: String)

    case createFolder(id: String, name: String, parentId: String?)
    case renameFolder(id: String, name: String, parentId: String?)
    case deleteFolder(id: String)

    /// The target id this change applies to. Used by the outbox to order /
    /// coalesce changes for the same document.
    public var targetId: String {
        switch self {
        case .createDocument(let id, _, _, _, _),
             .updateDocument(let id, _, _, _, _),
             .deleteDocument(let id),
             .createFolder(let id, _, _),
             .renameFolder(let id, _, _),
             .deleteFolder(let id):
            return id
        }
    }

    /// Coarse kind discriminator the outbox writes alongside the payload so
    /// repeated rows can be inspected without re-decoding the JSON payload.
    public var kind: Kind {
        switch self {
        case .createDocument: return .createDocument
        case .updateDocument: return .updateDocument
        case .deleteDocument: return .deleteDocument
        case .createFolder:   return .createFolder
        case .renameFolder:   return .renameFolder
        case .deleteFolder:   return .deleteFolder
        }
    }

    /// String token for outbox storage (`OutboxEntryRecord.kind`).
    public enum Kind: String, Sendable, Equatable {
        case createDocument
        case updateDocument
        case deleteDocument
        case createFolder
        case renameFolder
        case deleteFolder
    }
}

// MARK: - DocumentSyncReport

/// Summary of one `DocumentSyncEngine.syncNow()` cycle. The App layer surfaces
/// the counts in a banner / status bar; tests assert against these numbers.
public struct DocumentSyncReport: Sendable, Equatable {

    public let insertedDocumentIds: [Document.ID]
    public let updatedDocumentIds: [Document.ID]
    public let deletedDocumentIds: [Document.ID]
    public let insertedFolderIds: [FolderNode.ID]
    public let updatedFolderIds: [FolderNode.ID]
    public let deletedFolderIds: [FolderNode.ID]
    public let conflicts: [Conflict]
    public let pushedDocumentIds: [Document.ID]
    public let failedOutboxEntries: [FailedOutboxEntry]
    public let lastSyncAt: Date?

    public init(
        insertedDocumentIds: [Document.ID] = [],
        updatedDocumentIds: [Document.ID] = [],
        deletedDocumentIds: [Document.ID] = [],
        insertedFolderIds: [FolderNode.ID] = [],
        updatedFolderIds: [FolderNode.ID] = [],
        deletedFolderIds: [FolderNode.ID] = [],
        conflicts: [Conflict] = [],
        pushedDocumentIds: [Document.ID] = [],
        failedOutboxEntries: [FailedOutboxEntry] = [],
        lastSyncAt: Date? = nil
    ) {
        self.insertedDocumentIds = insertedDocumentIds
        self.updatedDocumentIds = updatedDocumentIds
        self.deletedDocumentIds = deletedDocumentIds
        self.insertedFolderIds = insertedFolderIds
        self.updatedFolderIds = updatedFolderIds
        self.deletedFolderIds = deletedFolderIds
        self.conflicts = conflicts
        self.pushedDocumentIds = pushedDocumentIds
        self.failedOutboxEntries = failedOutboxEntries
        self.lastSyncAt = lastSyncAt
    }

    /// One resolved conflict — the local copy was preserved under
    /// `preservedAs` and the server version applied to `original`.
    public struct Conflict: Sendable, Equatable {
        public let original: Document.ID
        public let preservedAs: Document.ID

        public init(original: Document.ID, preservedAs: Document.ID) {
            self.original = original
            self.preservedAs = preservedAs
        }
    }

    /// One outbox entry that failed to push during the cycle. Stays in the
    /// outbox so the next cycle can retry; surfaced in the report so the
    /// caller can show a "couldn't push N edits" banner.
    public struct FailedOutboxEntry: Sendable, Equatable {
        public let targetId: String
        public let kind: DocumentChange.Kind
        public let message: String

        public init(targetId: String, kind: DocumentChange.Kind, message: String) {
            self.targetId = targetId
            self.kind = kind
            self.message = message
        }
    }
}
