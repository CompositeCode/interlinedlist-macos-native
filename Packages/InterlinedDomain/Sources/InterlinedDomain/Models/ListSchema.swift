import Foundation

/// A single column in a list's schema (PLAN.md §1 "Structured lists", §6 M3).
///
/// Mirrors the `"Name:type"` pair in the schema DSL (`"Title:text"`,
/// `"Year:number"`). `nullable` and `enumValues` are reserved for future
/// per-type metadata as the upstream API documents it (see
/// `/API-backend-prompts-to-build.md` item 2.2); both are `nil` for the
/// starter set.
public struct SchemaField: Sendable, Equatable, Hashable, Identifiable {

    /// Column name as written in the DSL. Case- and whitespace-sensitive.
    public let name: String

    /// Column type.
    public let type: SchemaFieldType

    /// Whether the cell may be null. `nil` means "the DSL did not state it" —
    /// distinct from `false`, which means "the DSL declared this column NOT
    /// NULL". The starter parser does not consume this field; it is reserved
    /// for future DSL extensions per prompts file 2.2.
    public let nullable: Bool?

    /// For `enum(...)` columns, the closed set of allowed values. `nil` for
    /// non-enum columns. Reserved for the M3 schema-editor enum picker; the
    /// starter parser does not consume this field.
    public let enumValues: [String]?

    /// Identity is the column name (schemas forbid duplicates).
    public var id: String { name }

    public init(
        name: String,
        type: SchemaFieldType,
        nullable: Bool? = nil,
        enumValues: [String]? = nil
    ) {
        self.name = name
        self.type = type
        self.nullable = nullable
        self.enumValues = enumValues
    }
}

/// The parsed schema for a list.
///
/// Maps from `ListSchemaDTO.schema` (a DSL string) via `SchemaDSL.parse`, and
/// back via `SchemaDSL.serialize`. The ordered field array is the canonical
/// column order; the M3 row table renders columns in this order.
public struct ListSchema: Sendable, Equatable, Hashable {

    /// Ordered columns. Order is significant — the DSL preserves declaration
    /// order, and the editor / row table use it as the default column order.
    public let fields: [SchemaField]

    public init(fields: [SchemaField]) {
        self.fields = fields
    }

    /// The empty schema — a list with no declared columns. Boundary value
    /// for round-tripping `""` (rejected by the parser) and for tests.
    public static let empty = ListSchema(fields: [])

    /// Lookup helper used by the row-cell typed accessor (M3 schema editor).
    public func field(named name: String) -> SchemaField? {
        fields.first { $0.name == name }
    }
}
