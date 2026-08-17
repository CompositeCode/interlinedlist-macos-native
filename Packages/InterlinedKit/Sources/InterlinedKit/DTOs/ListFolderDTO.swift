import Foundation

// MARK: - List Folder DTOs (work-consolidation.md G6)
//
// Hierarchical folders for *lists* (distinct from document folders). Envelope
// verified live 2026-07-31: `GET /api/folders` → `{ folders: [...] }` (a flat
// array; clients rebuild the tree from each row's `parentId`). The folder rows
// were empty in the probe, so fields beyond `id`/`name` are modelled optional.

/// A single list folder. Nesting is expressed via `parentId` (`nil` at root).
public struct ListFolderDTO: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let parentId: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        name: String,
        parentId: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// `GET /api/folders` — `{ folders: [ListFolderDTO] }` (flat array, no pagination).
public struct ListFoldersResponse: Decodable, Sendable, Equatable {
    public let folders: [ListFolderDTO]

    public init(folders: [ListFolderDTO]) {
        self.folders = folders
    }
}

/// Body for `POST /api/folders`. `name` is 1–80 chars (validated in the domain
/// layer); `parentId` is `nil` for a root folder.
public struct CreateListFolderRequest: Encodable, Sendable, Equatable {
    public let name: String
    public let parentId: String?

    public init(name: String, parentId: String? = nil) {
        self.name = name
        self.parentId = parentId
    }
}

/// Body for `PUT /api/folders/{id}` — rename (`name`) and/or move (`parentId`).
/// Absent fields are left unchanged by the server. (Moving to the root, which
/// requires an explicit `parentId: null`, is a documented follow-up — Swift
/// optional encoding omits nil rather than emitting `null`.)
public struct UpdateListFolderRequest: Encodable, Sendable, Equatable {
    public let name: String?
    public let parentId: String?

    public init(name: String? = nil, parentId: String? = nil) {
        self.name = name
        self.parentId = parentId
    }
}
