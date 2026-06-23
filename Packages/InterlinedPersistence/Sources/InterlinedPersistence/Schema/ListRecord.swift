import Foundation
import SwiftData

/// SwiftData record for a cached `OwnedList` (PLAN.md §5 — lists cache).
///
/// Mirrors the round-trip surface of `InterlinedDomain.OwnedList`. The
/// schema fields are denormalised onto a single record (with the typed
/// per-column shape on `ListSchemaRecord` / `SchemaFieldRecord`) so the
/// list-row UI can render before the schema parser runs.
///
/// Internal to the package: `ListsStore` consumers only see `OwnedList`
/// values across the actor boundary.
@Model
final class ListRecord {

    @Attribute(.unique) var id: String

    var title: String
    var listDescription: String?
    /// Wire-shaped boolean (matches `OwnedList.visibility.isPubliclyVisible`);
    /// mapped to `Visibility` at the boundary.
    var publiclyVisible: Bool
    /// Raw schema DSL string; the typed parse lives on `ListSchemaRecord`.
    /// Carried here as well so a list can be displayed before the schema
    /// parser runs.
    var schemaDescription: String?
    var parentID: String?

    // GitHub-source metadata (`OwnedList.gitHubSource`). Flattened onto the
    // record rather than a separate `@Model` because every field is
    // optional and they are read together.
    var gitHubRepository: String?
    var gitHubPath: String?
    var gitHubBranch: String?
    var gitHubLastRefreshedAt: Date?
    var gitHubRefreshStatus: String?

    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: String,
        title: String,
        listDescription: String?,
        publiclyVisible: Bool,
        schemaDescription: String?,
        parentID: String?,
        gitHubRepository: String?,
        gitHubPath: String?,
        gitHubBranch: String?,
        gitHubLastRefreshedAt: Date?,
        gitHubRefreshStatus: String?,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.listDescription = listDescription
        self.publiclyVisible = publiclyVisible
        self.schemaDescription = schemaDescription
        self.parentID = parentID
        self.gitHubRepository = gitHubRepository
        self.gitHubPath = gitHubPath
        self.gitHubBranch = gitHubBranch
        self.gitHubLastRefreshedAt = gitHubLastRefreshedAt
        self.gitHubRefreshStatus = gitHubRefreshStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// SwiftData record for the ordered "all my lists" page — the lightweight
/// equivalent of `TimelinePageRecord`. Holds an ordered list of list ids;
/// the lists themselves are stored in `ListRecord` and hydrated by id.
///
/// A single-row table (keyed by a constant key) is good enough for M3
/// because the M3 brief only persists one owned-list page; if M5+ adds the
/// shared-with-me page, that becomes a second key here.
@Model
final class ListsPageRecord {
    /// Stable key — `"my-lists"` for the M3 owned page. Reserved for
    /// additional page kinds in future waves.
    @Attribute(.unique) var pageKey: String
    var listIDs: [String]
    var fetchedAt: Date

    init(pageKey: String, listIDs: [String], fetchedAt: Date) {
        self.pageKey = pageKey
        self.listIDs = listIDs
        self.fetchedAt = fetchedAt
    }
}
