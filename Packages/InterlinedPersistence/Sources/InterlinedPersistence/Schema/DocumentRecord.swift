import Foundation
import SwiftData

/// SwiftData record for a cached `Document` (PLAN.md §6 M4 — Documents).
///
/// Mirrors the round-trip surface of `InterlinedDomain.Document`. The
/// `localEditedAt` field is the only piece that does not appear on the
/// domain shape: it is `nil` when the local copy is in sync with the server,
/// and non-`nil` when the user has edited the document since the last
/// successful push. The `DocumentSyncEngine` uses this to detect conflicts
/// and to drive the outbox.
///
/// Internal to the package: `DocumentStore` consumers see only `Document`
/// values across the actor boundary.
@Model
final class DocumentRecord {

    @Attribute(.unique) var id: String

    var folderId: String?
    var title: String
    var bodyMarkdown: String
    var updatedAt: Date
    var createdAt: Date?
    var isPublic: Bool
    var deleted: Bool
    /// Server-supplied version / etag for conflict detection. `nil` when the
    /// API omits it (backend ask 3.1). The sync engine falls back to
    /// `updatedAt` comparisons when nil.
    var version: String?

    /// `nil` when the local copy is in sync. Set to `Date()` on local edits
    /// so the sync engine can both detect conflicts and prioritise the
    /// outbox push leg.
    var localEditedAt: Date?

    init(
        id: String,
        folderId: String?,
        title: String,
        bodyMarkdown: String,
        updatedAt: Date,
        createdAt: Date?,
        isPublic: Bool,
        deleted: Bool,
        version: String?,
        localEditedAt: Date?
    ) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.bodyMarkdown = bodyMarkdown
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.isPublic = isPublic
        self.deleted = deleted
        self.version = version
        self.localEditedAt = localEditedAt
    }
}
