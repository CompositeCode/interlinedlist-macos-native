import Foundation
import SwiftData

/// SwiftData record for a cached `ListRow`. Rows are stored per-list because
/// row ids are only meaningful in the context of their parent list
/// (`ListRowDTO.listId`).
///
/// The dynamic-schema `[String: ListCellValue]` map is encoded as a JSON
/// `Data` blob — SwiftData on macOS 14 does not yet have a first-class
/// dictionary-of-mixed-types column, and the JSON blob is cheap to round-
/// trip through the same `ListJSONValue` we already model.
///
/// Internal to the package.
@Model
final class ListRowRecord {

    @Attribute(.unique) var id: String
    var listID: String
    /// JSON-encoded `[String: ListJSONValue]`. The mapper layer encodes the
    /// domain `ListCellValue` via `ListJSONValue` so the on-disk shape stays
    /// stable across the M1 → M3 → future schema-aware refactors.
    var rowDataJSON: Data
    /// Stable position within the parent list's page. Used to round-trip
    /// page order across read/write cycles.
    var position: Int
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: String,
        listID: String,
        rowDataJSON: Data,
        position: Int,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.listID = listID
        self.rowDataJSON = rowDataJSON
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
