import Foundation

/// A single column in a list's schema (PLAN.md §1 "Structured lists", §6 M3).
///
/// The server keeps the column's **identity** and its **display name** apart —
/// `propertyKey` vs `propertyName` on the wire — and row data is keyed by the
/// identity:
///
/// ```json
/// "rowData": { "title": "Dune", "year": 1965 }
/// ```
///
/// This type had a single `name` doing both jobs, which was harmless only
/// because the client could not create a schema at all (GitHub #85: the server
/// rejects the DSL string the client sent). The moment that was fixed, a column
/// whose label differed from its key would have rendered every cell empty. So
/// `key` and `label` are separate here, and `key` is the identity.
///
/// The remaining fields are the per-column metadata the server has always
/// stored and the client never read — captured live 2026-09-15 and recorded in
/// `docs/spikes/list-schema-wire-shapes.md`. They unblock the validation and
/// help-text work in GitHub #50, which `work-consolidation.md` `P2-G` had listed
/// as API-unconfirmed.
public struct SchemaField: Sendable, Equatable, Hashable, Identifiable {

    /// The row-data key. `ListRow.fields` is keyed by this, **not** by `label`.
    public let key: String

    /// The display name shown in a column header and a row-form label.
    public let label: String

    /// Column type.
    public let type: SchemaFieldType

    /// Whether a row must supply a value. `nil` means the source did not say.
    public let isRequired: Bool?

    /// Whether the column is shown. A hidden column keeps its data — this is
    /// not deletion.
    public let isVisible: Bool?

    /// Zero-based column order as the server reports it. `nil` when the source
    /// was the client-side DSL, where array order is the only ordering.
    public let displayOrder: Int?

    /// Hint text shown under the field in a row form.
    public let helpText: String?

    /// Placeholder text for an empty field.
    public let placeholder: String?

    /// The column's default for a new row, as its own type would express it.
    public let defaultValue: ListCellValue?

    /// Per-type validation rules the server enforces.
    public let validation: SchemaFieldValidation?

    /// For `select` columns, the closed set of allowed values.
    public let enumValues: [String]?

    /// Legacy spelling of `label`, kept because the DSL — where a column's key
    /// and its label are the same token — is still how lists are authored by
    /// hand in the New List sheet.
    ///
    /// - Warning: never use this to index `ListRow.fields`. Use ``key``.
    public var name: String { label }

    /// Whether the cell may be null.
    ///
    /// Inverted view of ``isRequired`` and kept for the callers that read it.
    /// `nil` when the source stated neither.
    public var nullable: Bool? {
        guard let isRequired else { return nil }
        return !isRequired
    }

    /// Identity is the column key (schemas forbid duplicate keys).
    public var id: String { key }

    /// Hashed on identity alone.
    ///
    /// Written out rather than synthesised because `defaultValue` is a
    /// `ListCellValue`, which is deliberately `Equatable` but not `Hashable` —
    /// it can carry arbitrary nested JSON. Hashing the key is both cheaper and
    /// the correct notion of identity for a column.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }

    /// Full initialiser — used when projecting a server payload, which supplies
    /// a distinct key and label.
    public init(
        key: String,
        label: String,
        type: SchemaFieldType,
        isRequired: Bool? = nil,
        isVisible: Bool? = nil,
        displayOrder: Int? = nil,
        helpText: String? = nil,
        placeholder: String? = nil,
        defaultValue: ListCellValue? = nil,
        validation: SchemaFieldValidation? = nil,
        enumValues: [String]? = nil
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.isVisible = isVisible
        self.displayOrder = displayOrder
        self.helpText = helpText
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.validation = validation
        self.enumValues = enumValues
    }

    /// DSL initialiser — the hand-authored case, where the one token the user
    /// typed is both the key and the label.
    public init(
        name: String,
        type: SchemaFieldType,
        nullable: Bool? = nil,
        enumValues: [String]? = nil
    ) {
        self.init(
            key: name,
            label: name,
            type: type,
            isRequired: nullable.map { !$0 },
            enumValues: enumValues
        )
    }
}

/// The validation rules the server stores against a column.
///
/// Every rule is optional and they combine per type: `text` carries
/// `minLength`/`maxLength`/`pattern`, `number` carries `min`/`max`, `select`
/// carries its options (surfaced on `SchemaField.enumValues`).
///
/// `pattern` is deliberately **not** evaluated client-side. It is a server-side
/// regular expression, and pre-validating it against a different engine would
/// let the client reject a value the server would accept — a worse failure than
/// a round-trip.
public struct SchemaFieldValidation: Sendable, Equatable, Hashable {
    public let min: Double?
    public let max: Double?
    public let minLength: Int?
    public let maxLength: Int?
    public let pattern: String?

    public init(
        min: Double? = nil,
        max: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil
    ) {
        self.min = min
        self.max = max
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
    }

    /// `true` when no rule is set. A column with an empty rule set should send
    /// no `validation` object at all rather than an empty one, which the server
    /// reads as "clear the rules".
    public var isEmpty: Bool {
        min == nil && max == nil && minLength == nil && maxLength == nil && pattern == nil
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

    /// Lookup by column **key** — the identity `ListRow.fields` is keyed by.
    public func field(key: String) -> SchemaField? {
        fields.first { $0.key == key }
    }

    /// Lookup helper used by the row-cell typed accessor (M3 schema editor).
    ///
    /// Matches on `key` first and falls back to `label`, because callers that
    /// predate the key/label split pass whichever one they had — and for a
    /// DSL-authored schema the two are the same token anyway.
    public func field(named name: String) -> SchemaField? {
        fields.first { $0.key == name } ?? fields.first { $0.label == name }
    }

    /// The columns in the order the UI should render them: `displayOrder` when
    /// the server supplied it, declaration order otherwise.
    public var orderedFields: [SchemaField] {
        guard fields.contains(where: { $0.displayOrder != nil }) else { return fields }
        return fields.enumerated()
            .sorted { ($0.element.displayOrder ?? $0.offset) < ($1.element.displayOrder ?? $1.offset) }
            .map(\.element)
    }
}
