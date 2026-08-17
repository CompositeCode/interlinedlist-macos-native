import Foundation
import InterlinedKit

// MARK: - ListFolder

/// A folder that organizes the current user's lists (work-consolidation.md G6). Nesting
/// is expressed via `parentId`; the App rebuilds the tree with `ListFolder.tree`.
public struct ListFolder: Sendable, Equatable, Hashable, Identifiable {
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

extension ListFolder {
    /// Maps a `ListFolderDTO` to the domain value (decision 0003 boundary).
    public init(from dto: ListFolderDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            parentId: dto.parentId,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

// MARK: - ListFolderNode (tree)

/// A node in the assembled folder tree. `children` are ordered as they appear
/// in the source array.
public struct ListFolderNode: Sendable, Equatable, Hashable, Identifiable {
    public let folder: ListFolder
    public let children: [ListFolderNode]

    public var id: String { folder.id }
    public var name: String { folder.name }

    public init(folder: ListFolder, children: [ListFolderNode] = []) {
        self.folder = folder
        self.children = children
    }
}

extension ListFolder {
    /// Assembles a flat folder array into a root-level tree. A folder whose
    /// `parentId` is `nil` — or points to a folder not present in the array —
    /// becomes a root (so the caller never loses a folder to a dangling
    /// parent). Cycles are broken defensively: a node is only ever attached
    /// once, so a folder that (transitively) parents itself lands at root.
    public static func tree(from folders: [ListFolder]) -> [ListFolderNode] {
        let byId = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var childIds: [String: [String]] = [:]
        var rootIds: [String] = []
        for folder in folders {
            if let parentId = folder.parentId, byId[parentId] != nil, parentId != folder.id {
                childIds[parentId, default: []].append(folder.id)
            } else {
                rootIds.append(folder.id)
            }
        }

        func build(_ id: String, visited: Set<String>) -> ListFolderNode? {
            guard let folder = byId[id], !visited.contains(id) else { return nil }
            let nextVisited = visited.union([id])
            let children = (childIds[id] ?? []).compactMap { build($0, visited: nextVisited) }
            return ListFolderNode(folder: folder, children: children)
        }

        return rootIds.compactMap { build($0, visited: []) }
    }
}
