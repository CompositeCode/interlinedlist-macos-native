// StubDocumentsService
//
// Deterministic `DocumentsServicing` stub for App-layer view-model tests
// of the M4 Documents feature. Mirrors `StubListsService`: an actor with
// a queued outcome list per call site and a recorded-call log. Only
// the entry points the Wave 5.3 view models exercise are implemented;
// the rest throw a `notProgrammed` error so unprepared paths fail
// loudly.

import Foundation
import InterlinedDomain

struct RecordedDocumentsCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case documents(folderId: String?, limit: Int, offset: Int)
        case document(id: String)
        case create(title: String, body: String, folderId: String?, isPublic: Bool)
        case createInFolder(folderId: String, title: String, body: String, isPublic: Bool, relativePath: String?)
        case moveDocument(id: String, toFolder: String?)
        case documentTree
        case publicDocuments(username: String)
        case invite(token: String)
        case update(id: String, title: String?, body: String?, folderId: String?, isPublic: Bool?)
        case delete(id: String)
        case uploadImage(documentId: String, byteCount: Int, suggestedName: String?)
        case folders(limit: Int, offset: Int)
        case folder(id: String)
        case createFolder(name: String, parentId: String?)
        case renameFolder(id: String, name: String)
        case deleteFolder(id: String)
        case syncNow
        case enqueueOfflineWrite(kind: DocumentChange.Kind, targetId: String)
    }
    let kind: Kind
}

actor StubDocumentsService: DocumentsServicing {

    // MARK: Outcome queues

    private var documentsOutcomes: [Result<[Document], Error>] = []
    private var documentOutcomes: [Result<Document, Error>] = []
    private var createOutcomes: [Result<Document, Error>] = []
    private var createInFolderOutcomes: [Result<Document, Error>] = []
    private var moveOutcomes: [Result<Document, Error>] = []
    private var treeOutcomes: [Result<DocumentTreeSnapshot, Error>] = []
    private var publicDocumentsOutcomes: [Result<PublicUserDocuments, Error>] = []
    private var inviteOutcomes: [Result<DocumentInvite, Error>] = []
    private var updateOutcomes: [Result<Document, Error>] = []
    private var deleteOutcomes: [Result<Void, Error>] = []
    private var uploadImageOutcomes: [Result<URL, Error>] = []
    private var foldersOutcomes: [Result<[FolderNode], Error>] = []
    private var folderOutcomes: [Result<FolderNode, Error>] = []
    private var createFolderOutcomes: [Result<FolderNode, Error>] = []
    private var renameFolderOutcomes: [Result<FolderNode, Error>] = []
    private var deleteFolderOutcomes: [Result<Void, Error>] = []
    private var syncOutcomes: [Result<DocumentSyncReport, Error>] = []

    /// Cache-first read surface (PLAN.md §5 SWR). Default `[]` so unprepared
    /// paths behave like a cold cache; enqueue a value to prime a paint-first
    /// test for the later view-model wiring pass.
    private var cachedDocumentsByFolder: [String: [Document]] = [:]
    private var cachedRootDocuments: [Document] = []
    private var cachedFoldersValue: [FolderNode] = []

    private(set) var recorded: [RecordedDocumentsCall] = []

    // MARK: Programmable enqueue helpers

    func enqueueDocuments(success page: [Document]) { documentsOutcomes.append(.success(page)) }
    func enqueueDocuments(failure error: Error) { documentsOutcomes.append(.failure(error)) }

    func enqueueDocument(success doc: Document) { documentOutcomes.append(.success(doc)) }
    func enqueueDocument(failure error: Error) { documentOutcomes.append(.failure(error)) }

    func enqueueCreate(success doc: Document) { createOutcomes.append(.success(doc)) }
    func enqueueCreate(failure error: Error) { createOutcomes.append(.failure(error)) }

    func enqueueCreateInFolder(success doc: Document) { createInFolderOutcomes.append(.success(doc)) }
    func enqueueCreateInFolder(failure error: Error) { createInFolderOutcomes.append(.failure(error)) }

    func enqueueMove(success doc: Document) { moveOutcomes.append(.success(doc)) }
    func enqueueMove(failure error: Error) { moveOutcomes.append(.failure(error)) }

    func enqueueTree(success tree: DocumentTreeSnapshot) { treeOutcomes.append(.success(tree)) }
    func enqueueTree(failure error: Error) { treeOutcomes.append(.failure(error)) }

    /// Programs a tree that carries `folders` and no documents. The sidebar
    /// reads folders from the tree since G24, so tests that only care about
    /// the folder list say so without building a document index.
    func enqueueTree(foldersOnly folders: [FolderNode]) {
        treeOutcomes.append(.success(DocumentTreeSnapshot(folders: folders)))
    }

    func enqueuePublicDocuments(success result: PublicUserDocuments) { publicDocumentsOutcomes.append(.success(result)) }
    func enqueuePublicDocuments(failure error: Error) { publicDocumentsOutcomes.append(.failure(error)) }

    func enqueueInvite(success invite: DocumentInvite) { inviteOutcomes.append(.success(invite)) }
    func enqueueInvite(failure error: Error) { inviteOutcomes.append(.failure(error)) }

    func enqueueUpdate(success doc: Document) { updateOutcomes.append(.success(doc)) }
    func enqueueUpdate(failure error: Error) { updateOutcomes.append(.failure(error)) }

    func enqueueDeleteSuccess() { deleteOutcomes.append(.success(())) }
    func enqueueDelete(failure error: Error) { deleteOutcomes.append(.failure(error)) }

    func enqueueUploadImage(success url: URL) { uploadImageOutcomes.append(.success(url)) }
    func enqueueUploadImage(failure error: Error) { uploadImageOutcomes.append(.failure(error)) }

    func enqueueFolders(success folders: [FolderNode]) { foldersOutcomes.append(.success(folders)) }
    func enqueueFolders(failure error: Error) { foldersOutcomes.append(.failure(error)) }

    func enqueueFolder(success folder: FolderNode) { folderOutcomes.append(.success(folder)) }

    func enqueueCreateFolder(success folder: FolderNode) { createFolderOutcomes.append(.success(folder)) }
    func enqueueCreateFolder(failure error: Error) { createFolderOutcomes.append(.failure(error)) }

    func enqueueRenameFolder(success folder: FolderNode) { renameFolderOutcomes.append(.success(folder)) }
    func enqueueRenameFolder(failure error: Error) { renameFolderOutcomes.append(.failure(error)) }

    func enqueueDeleteFolderSuccess() { deleteFolderOutcomes.append(.success(())) }
    func enqueueDeleteFolder(failure error: Error) { deleteFolderOutcomes.append(.failure(error)) }

    func enqueueSync(success report: DocumentSyncReport) { syncOutcomes.append(.success(report)) }
    func enqueueSync(failure error: Error) { syncOutcomes.append(.failure(error)) }

    /// Primes the cache-first read surface for a paint-first test.
    func setCachedDocuments(_ documents: [Document], in folderID: FolderNode.ID?) {
        if let folderID { cachedDocumentsByFolder[folderID] = documents }
        else { cachedRootDocuments = documents }
    }
    func setCachedFolders(_ folders: [FolderNode]) { cachedFoldersValue = folders }

    // MARK: DocumentsServicing

    func documents(in folder: FolderNode.ID?, limit: Int, offset: Int) async throws -> [Document] {
        recorded.append(.init(kind: .documents(folderId: folder, limit: limit, offset: offset)))
        return try take(&documentsOutcomes, label: "documents")
    }

    func cachedDocuments(in folderID: FolderNode.ID?) async -> [Document] {
        if let folderID { return cachedDocumentsByFolder[folderID] ?? [] }
        return cachedRootDocuments
    }

    func cachedFolders() async -> [FolderNode] { cachedFoldersValue }

    func document(id: String) async throws -> Document {
        recorded.append(.init(kind: .document(id: id)))
        return try take(&documentOutcomes, label: "document")
    }

    func create(title: String, body: String, folderId: String?, isPublic: Bool) async throws -> Document {
        recorded.append(.init(kind: .create(title: title, body: body, folderId: folderId, isPublic: isPublic)))
        return try take(&createOutcomes, label: "create")
    }

    func createDocument(
        inFolder folderId: String,
        title: String,
        body: String,
        isPublic: Bool,
        relativePath: String?
    ) async throws -> Document {
        recorded.append(.init(kind: .createInFolder(
            folderId: folderId,
            title: title,
            body: body,
            isPublic: isPublic,
            relativePath: relativePath
        )))
        return try take(&createInFolderOutcomes, label: "createDocument(inFolder:)")
    }

    func moveDocument(id: String, toFolder folderId: String?) async throws -> Document {
        recorded.append(.init(kind: .moveDocument(id: id, toFolder: folderId)))
        return try take(&moveOutcomes, label: "moveDocument")
    }

    func documentTree() async throws -> DocumentTreeSnapshot {
        recorded.append(.init(kind: .documentTree))
        return try take(&treeOutcomes, label: "documentTree")
    }

    func publicDocuments(ofUser username: String) async throws -> PublicUserDocuments {
        recorded.append(.init(kind: .publicDocuments(username: username)))
        return try take(&publicDocumentsOutcomes, label: "publicDocuments")
    }

    func invite(token: String) async throws -> DocumentInvite {
        recorded.append(.init(kind: .invite(token: token)))
        return try take(&inviteOutcomes, label: "invite")
    }

    func update(id: String, title: String?, body: String?, folderId: String?, isPublic: Bool?) async throws -> Document {
        recorded.append(.init(kind: .update(id: id, title: title, body: body, folderId: folderId, isPublic: isPublic)))
        return try take(&updateOutcomes, label: "update")
    }

    func delete(id: String) async throws {
        recorded.append(.init(kind: .delete(id: id)))
        let _: Void = try take(&deleteOutcomes, label: "delete")
    }

    func uploadImage(in documentId: String, image: Data, suggestedName: String?) async throws -> URL {
        recorded.append(.init(kind: .uploadImage(documentId: documentId, byteCount: image.count, suggestedName: suggestedName)))
        return try take(&uploadImageOutcomes, label: "uploadImage")
    }

    func folders(limit: Int, offset: Int) async throws -> [FolderNode] {
        recorded.append(.init(kind: .folders(limit: limit, offset: offset)))
        return try take(&foldersOutcomes, label: "folders")
    }

    func folder(id: String) async throws -> FolderNode {
        recorded.append(.init(kind: .folder(id: id)))
        return try take(&folderOutcomes, label: "folder")
    }

    func createFolder(name: String, parentId: String?) async throws -> FolderNode {
        recorded.append(.init(kind: .createFolder(name: name, parentId: parentId)))
        return try take(&createFolderOutcomes, label: "createFolder")
    }

    func renameFolder(id: String, to name: String) async throws -> FolderNode {
        recorded.append(.init(kind: .renameFolder(id: id, name: name)))
        return try take(&renameFolderOutcomes, label: "renameFolder")
    }

    func deleteFolder(id: String) async throws {
        recorded.append(.init(kind: .deleteFolder(id: id)))
        let _: Void = try take(&deleteFolderOutcomes, label: "deleteFolder")
    }

    func syncNow() async throws -> DocumentSyncReport {
        recorded.append(.init(kind: .syncNow))
        return try take(&syncOutcomes, label: "syncNow")
    }

    func enqueueOfflineWrite(_ change: DocumentChange) async {
        recorded.append(.init(kind: .enqueueOfflineWrite(kind: change.kind, targetId: change.targetId)))
    }

    nonisolated var syncEvents: AsyncStream<DocumentSyncEvent>? { nil }

    // MARK: - Internals

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else { throw StubError.notProgrammed(label) }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubError: Error, Equatable {
        case notProgrammed(String)
    }
}

// MARK: - Convenience fixtures

enum DocumentsFixtures {
    static func folder(
        id: String,
        name: String = "Folder",
        parentId: String? = nil
    ) -> FolderNode {
        FolderNode(
            id: id,
            parentId: parentId,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func document(
        id: String,
        folderId: String? = nil,
        title: String = "Doc",
        body: String = "",
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        isPublic: Bool = false
    ) -> Document {
        Document(
            id: id,
            folderId: folderId,
            title: title,
            body: DocumentBody(markdown: body),
            updatedAt: updatedAt,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPublic: isPublic
        )
    }

    /// A `DocumentTreeSnapshot` from a compact `[folderName: [documentTitle]]`
    /// description, so a test can say what shape it wants without hand-building
    /// the folder / summary graph.
    ///
    /// Folder ids are derived from the name (`"Inbox"` → `"F-Inbox"`) and
    /// document ids from the title, so assertions can name them directly.
    /// `parents` re-parents a folder to build a nested tree.
    static func tree(
        folders: [(name: String, documents: [String])] = [],
        rootDocuments: [String] = [],
        parents: [String: String] = [:]
    ) -> DocumentTreeSnapshot {
        var nodes: [FolderNode] = []
        var index: [String: [DocumentSummary]] = [:]
        for entry in folders {
            let id = "F-\(entry.name)"
            nodes.append(
                FolderNode(
                    id: id,
                    parentId: parents[entry.name].map { "F-\($0)" },
                    name: entry.name
                )
            )
            index[id] = entry.documents.map {
                DocumentSummary(id: "D-\($0)", title: $0, folderId: id)
            }
        }
        return DocumentTreeSnapshot(
            folders: nodes,
            documentsByFolder: index,
            rootDocuments: rootDocuments.map {
                DocumentSummary(id: "D-\($0)", title: $0, folderId: nil)
            }
        )
    }

    static func invite(
        token: String = "tok",
        role: String = "collaborator",
        resourceTitle: String? = "Q3 Planning",
        needsAuth: Bool = false,
        canClaim: Bool = true,
        wrongAccount: Bool = false,
        accepted: Bool = false
    ) -> DocumentInvite {
        DocumentInvite(
            token: token,
            role: role,
            resourceTitle: resourceTitle,
            needsAuth: needsAuth,
            canClaim: canClaim,
            wrongAccount: wrongAccount,
            accepted: accepted
        )
    }

    static func emptyReport(lastSyncAt: Date? = nil) -> DocumentSyncReport {
        DocumentSyncReport(lastSyncAt: lastSyncAt)
    }
}
