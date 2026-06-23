import Foundation
import SwiftData

/// SwiftData record for a cached typed schema. Sits alongside `ListRecord`
/// so the M3 typed-row editor can render columns without re-running the
/// DSL parser on every render.
///
/// Keyed by the owning `listID` — exactly one schema per list. The fields
/// are stored as a `[SchemaFieldRecord]` and re-emitted in declaration
/// order on read.
@Model
final class ListSchemaRecord {

    @Attribute(.unique) var listID: String
    /// Ordered columns. SwiftData relationships preserve insertion order
    /// on a `to-many` relationship by default on macOS 14.
    @Relationship(deleteRule: .cascade)
    var fields: [SchemaFieldRecord]

    init(listID: String, fields: [SchemaFieldRecord]) {
        self.listID = listID
        self.fields = fields
    }
}

/// SwiftData record for a single schema column.
///
/// `position` is stored explicitly so reads preserve DSL declaration order
/// even if the underlying relationship implementation re-orders.
@Model
final class SchemaFieldRecord {

    /// Stable position (0-based) within the parent schema's field array.
    var position: Int
    var name: String
    /// Wire token (`"text"`, `"number"`, …). Mapped to `SchemaFieldType`
    /// at the boundary; unknown tokens (which the in-process parser would
    /// reject) are tolerated by the cache so old-shape rows never crash
    /// the store.
    var typeToken: String
    var nullable: Bool?
    var enumValues: [String]?

    init(
        position: Int,
        name: String,
        typeToken: String,
        nullable: Bool?,
        enumValues: [String]?
    ) {
        self.position = position
        self.name = name
        self.typeToken = typeToken
        self.nullable = nullable
        self.enumValues = enumValues
    }
}
