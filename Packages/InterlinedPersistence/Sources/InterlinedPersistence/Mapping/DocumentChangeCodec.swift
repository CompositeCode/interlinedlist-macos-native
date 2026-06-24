import Foundation
import InterlinedDomain

/// JSON codec for `DocumentChange`. The outbox stores changes as JSON-encoded
/// blobs (so the `OutboxEntryRecord` row stays a flat scalar set even as new
/// change kinds are added). This codec is the one place the wire shape is
/// defined; the engine encodes on enqueue and decodes on push.
enum DocumentChangeCodec {

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        JSONDecoder()
    }()

    // MARK: - Codable wire shape

    /// Internal `Codable` mirror of `DocumentChange`. Lives in this file so
    /// the domain enum doesn't have to be `Codable` (its API surface is
    /// intentionally narrow).
    fileprivate struct Wire: Codable, Equatable {
        var kind: String
        var id: String
        var title: String?
        var body: String?
        var folderId: String?
        var isPublic: Bool?
        var name: String?
        var parentId: String?
    }

    static func encode(_ change: DocumentChange) throws -> Data {
        let wire: Wire
        switch change {
        case .createDocument(let id, let folderId, let title, let body, let isPublic):
            wire = Wire(
                kind: DocumentChange.Kind.createDocument.rawValue,
                id: id,
                title: title,
                body: body,
                folderId: folderId,
                isPublic: isPublic
            )
        case .updateDocument(let id, let title, let body, let folderId, let isPublic):
            wire = Wire(
                kind: DocumentChange.Kind.updateDocument.rawValue,
                id: id,
                title: title,
                body: body,
                folderId: folderId,
                isPublic: isPublic
            )
        case .deleteDocument(let id):
            wire = Wire(kind: DocumentChange.Kind.deleteDocument.rawValue, id: id)
        case .createFolder(let id, let name, let parentId):
            wire = Wire(
                kind: DocumentChange.Kind.createFolder.rawValue,
                id: id,
                name: name,
                parentId: parentId
            )
        case .renameFolder(let id, let name, let parentId):
            wire = Wire(
                kind: DocumentChange.Kind.renameFolder.rawValue,
                id: id,
                name: name,
                parentId: parentId
            )
        case .deleteFolder(let id):
            wire = Wire(kind: DocumentChange.Kind.deleteFolder.rawValue, id: id)
        }
        return try encoder.encode(wire)
    }

    static func decode(_ data: Data) throws -> DocumentChange {
        let wire = try decoder.decode(Wire.self, from: data)
        guard let kind = DocumentChange.Kind(rawValue: wire.kind) else {
            throw DocumentChangeCodecError.unknownKind(wire.kind)
        }
        switch kind {
        case .createDocument:
            return .createDocument(
                id: wire.id,
                folderId: wire.folderId,
                title: wire.title ?? "",
                body: wire.body ?? "",
                isPublic: wire.isPublic ?? false
            )
        case .updateDocument:
            return .updateDocument(
                id: wire.id,
                title: wire.title,
                body: wire.body,
                folderId: wire.folderId,
                isPublic: wire.isPublic
            )
        case .deleteDocument:
            return .deleteDocument(id: wire.id)
        case .createFolder:
            return .createFolder(id: wire.id, name: wire.name ?? "", parentId: wire.parentId)
        case .renameFolder:
            return .renameFolder(id: wire.id, name: wire.name ?? "", parentId: wire.parentId)
        case .deleteFolder:
            return .deleteFolder(id: wire.id)
        }
    }
}

enum DocumentChangeCodecError: Error, Equatable {
    case unknownKind(String)
}
