import Foundation
@testable import InterlinedListSyncCore

/// In-memory stand-in for the InterlinedList documents API, used by the engine
/// integration tests. Deterministic clock; control methods to simulate
/// server-side edits/deletes.
actor FakeServer: DocumentSyncAPI {

    private var docs: [String: RemoteDocument] = [:]
    private var tombstones: [String: Date] = [:]
    private var folders: [String: RemoteFolder] = [:]
    private var version = Date(timeIntervalSince1970: 1_000_000)
    private var idSeq = 0

    /// When false, deletions are not surfaced in the delta (forces the engine
    /// to rely on the full-list reconciliation safety net).
    var deliverTombstones = true

    private(set) var createdBodies: [String] = []

    private func bump() -> Date {
        version = version.addingTimeInterval(1)
        return version
    }

    // MARK: - Test control

    func setDeliverTombstones(_ value: Bool) { deliverTombstones = value }

    func seedFolder(id: String, name: String, parentId: String? = nil) {
        folders[id] = RemoteFolder(id: id, name: name, parentId: parentId)
    }

    @discardableResult
    func seedDocument(id: String, title: String, content: String, folderId: String? = nil) -> RemoteDocument {
        let doc = RemoteDocument(id: id, title: title, content: content, folderId: folderId, updatedAt: bump())
        docs[id] = doc
        return doc
    }

    func serverEdit(id: String, content: String) {
        guard let existing = docs[id] else { return }
        docs[id] = RemoteDocument(
            id: id, title: existing.title, content: content,
            folderId: existing.folderId, updatedAt: bump()
        )
    }

    func serverDelete(id: String) {
        docs[id] = nil
        tombstones[id] = bump()
    }

    func document(id: String) -> RemoteDocument? { docs[id] }
    func documentCount() -> Int { docs.count }

    // MARK: - DocumentSyncAPI

    func fetchDelta(since: Date?) async throws -> DeltaResponse {
        let changed = docs.values
            .filter { since == nil || $0.updatedAt > since! }
            .map { DocumentDelta(id: $0.id, title: $0.title, content: $0.content, folderId: $0.folderId, updatedAt: $0.updatedAt) }
        var deltas = Array(changed)
        if deliverTombstones {
            for (id, at) in tombstones where since == nil || at > since! {
                deltas.append(DocumentDelta(id: id, title: "", content: nil, folderId: nil, updatedAt: at, deletedAt: at))
            }
        }
        return DeltaResponse(lastSyncAt: version, documents: deltas, folders: Array(folders.values))
    }

    func fetchAllDocuments() async throws -> [RemoteDocument] { Array(docs.values) }

    func fetchDocument(id: String) async throws -> RemoteDocument {
        guard let doc = docs[id] else { throw APIError.notFound }
        return doc
    }

    func createDocument(_ body: CreateDocumentBody) async throws -> RemoteDocument {
        idSeq += 1
        let id = "srv-\(idSeq)"
        createdBodies.append(body.content)
        let doc = RemoteDocument(id: id, title: body.title, content: body.content, folderId: body.folderId, updatedAt: bump())
        docs[id] = doc
        return doc
    }

    func updateDocument(id: String, _ body: UpdateDocumentBody) async throws -> RemoteDocument {
        guard let existing = docs[id] else { throw APIError.notFound }
        let doc = RemoteDocument(
            id: id,
            title: body.title ?? existing.title,
            content: body.content ?? existing.content,
            folderId: body.folderId ?? existing.folderId,
            updatedAt: bump()
        )
        docs[id] = doc
        return doc
    }

    func deleteDocument(id: String) async throws {
        docs[id] = nil
        tombstones[id] = bump()
    }

    func fetchAllFolders() async throws -> [RemoteFolder] { Array(folders.values) }

    func createFolder(_ body: CreateFolderBody) async throws -> RemoteFolder {
        idSeq += 1
        let id = "fld-\(idSeq)"
        let folder = RemoteFolder(id: id, name: body.name, parentId: body.parentId)
        folders[id] = folder
        return folder
    }
}
