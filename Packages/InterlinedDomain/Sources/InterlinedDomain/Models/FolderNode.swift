import Foundation

// MARK: - FolderNode

/// A document folder (PLAN.md §1 "Documents — folder source list").
///
/// Folders are flat in the wire model — each has a `parentId` (nil for the
/// root). `FolderTree` projects them into a parent/children index for sidebar
/// rendering.
public struct FolderNode: Sendable, Equatable, Hashable, Identifiable {

    public let id: String
    public let parentId: String?
    public let name: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let deleted: Bool

    public init(
        id: String,
        parentId: String? = nil,
        name: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deleted: Bool = false
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

// MARK: - FolderTree

/// Convenience projection over a flat `[FolderNode]` for sidebar rendering.
///
/// Holds the original ordered list plus a `roots`/`children` index so the
/// view layer can render the tree without recomputing the structure on
/// every redraw. Stable across equal inputs (folders ordered by their
/// original input order within each parent group, matching the API's
/// `createdAt`-sorted default).
public struct FolderTree: Sendable, Equatable {

    /// Every folder in the tree.
    public let folders: [FolderNode]

    /// Root folders (those with `parentId == nil`), in input order.
    public let roots: [FolderNode]

    /// Children index keyed by parent id, in input order within each group.
    public let childrenByParent: [String: [FolderNode]]

    public init(folders: [FolderNode]) {
        // Drop tombstoned folders from the projection so the sidebar never
        // shows a folder that was deleted upstream.
        let live = folders.filter { !$0.deleted }
        self.folders = live

        var roots: [FolderNode] = []
        var index: [String: [FolderNode]] = [:]
        for folder in live {
            if let parent = folder.parentId {
                index[parent, default: []].append(folder)
            } else {
                roots.append(folder)
            }
        }
        self.roots = roots
        self.childrenByParent = index
    }

    /// The direct children of `parentId`, in input order. `nil` parentId
    /// returns the roots.
    public func children(of parentId: String?) -> [FolderNode] {
        guard let parentId else { return roots }
        return childrenByParent[parentId] ?? []
    }
}
