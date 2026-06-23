import Foundation
import SwiftData

/// SwiftData record for a cached `ListConnection` (the ERD graph edge).
///
/// Connections are global (a single global response from
/// `GET /api/lists/connections`), so the cache is a flat collection keyed
/// by id rather than per-list. The filter-by-list view is computed at read
/// time.
///
/// Internal to the package.
@Model
final class ListConnectionRecord {

    @Attribute(.unique) var id: String
    var fromListID: String
    var toListID: String
    var label: String?
    var createdAt: Date?

    init(
        id: String,
        fromListID: String,
        toListID: String,
        label: String?,
        createdAt: Date?
    ) {
        self.id = id
        self.fromListID = fromListID
        self.toListID = toListID
        self.label = label
        self.createdAt = createdAt
    }
}
