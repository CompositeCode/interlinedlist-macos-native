import Foundation
import SwiftData

/// SwiftData record for a cached `ListWatcher` entry. Keyed by `(listID,
/// userID)` together — the same user can watch many lists, and many users
/// can watch one list. SwiftData v1 has no native composite primary key,
/// so the store enforces uniqueness via fetch-then-mutate (`mergeUpsert`).
///
/// Internal to the package.
@Model
final class ListWatcherRecord {

    var listID: String
    var userID: String
    var username: String?
    /// Wire role token; unknown tokens preserve under `WatcherRole.other(_)`
    /// at the boundary so the cache survives unrecognised server values.
    var roleToken: String
    var createdAt: Date?

    init(
        listID: String,
        userID: String,
        username: String?,
        roleToken: String,
        createdAt: Date?
    ) {
        self.listID = listID
        self.userID = userID
        self.username = username
        self.roleToken = roleToken
        self.createdAt = createdAt
    }
}
