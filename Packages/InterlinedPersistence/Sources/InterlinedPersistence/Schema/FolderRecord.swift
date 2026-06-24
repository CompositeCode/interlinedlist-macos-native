import Foundation
import SwiftData

/// SwiftData record for a cached `FolderNode` (PLAN.md §6 M4 — Documents).
///
/// Mirrors the round-trip surface of `InterlinedDomain.FolderNode`.
@Model
final class FolderRecord {

    @Attribute(.unique) var id: String

    var parentId: String?
    var name: String
    var createdAt: Date?
    var updatedAt: Date?
    var deleted: Bool

    init(
        id: String,
        parentId: String?,
        name: String,
        createdAt: Date?,
        updatedAt: Date?,
        deleted: Bool
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}
