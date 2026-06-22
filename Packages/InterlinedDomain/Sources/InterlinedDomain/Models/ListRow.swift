import Foundation
import InterlinedKit

/// A loose, type-erased cell value for a list row in M1.
///
/// The kit's `ListJSONValue` is the wire-faithful tagged union; the M1 read-
/// only UI does not yet need the typed schema, so the domain exposes a
/// projection that the view layer can render as text directly. The M3 schema
/// editor work will introduce a typed-per-column accessor that interprets
/// these values against the parsed schema (PLAN.md §6 M3, §7 "Schema DSL
/// parser").
public enum ListCellValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    /// A JSON array — rendered as `"[...]"` in M1; structured rendering lands
    /// when the schema editor does.
    case array([ListCellValue])
    /// A JSON object — rendered as `"{...}"` in M1.
    case object([String: ListCellValue])

    /// Human-readable rendering for the M1 read-only grid. Plain string-like
    /// values render as themselves; structured values render compactly so the
    /// table never shows a raw Swift `Optional(.array(...))` dump.
    public var displayText: String {
        switch self {
        case .null: return ""
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .string(let v): return v
        case .array(let v): return "[\(v.count) items]"
        case .object(let v): return "{\(v.count) fields}"
        }
    }
}

/// A single dynamic-schema row, projected as a field-name → cell map.
///
/// Maps from `ListRowDTO`. M1 keeps the row shape loose so the read-only
/// browser can render rows without the schema DSL parser; M3 introduces the
/// typed accessor that pairs each cell with its declared column type.
public struct ListRow: Sendable, Equatable, Identifiable {
    public let id: String
    /// The owning list id when the row payload includes it.
    public let listID: String?
    /// Field-name → cell value, in no defined order. The schema string on the
    /// owning `ListDetail` defines the canonical column order for rendering.
    public let fields: [String: ListCellValue]
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        listID: String? = nil,
        fields: [String: ListCellValue],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.listID = listID
        self.fields = fields
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One page of rows from a public list — the same shape as `ListsPage` /
/// `TimelinePage` so the App layer's pagination machinery is uniform.
public struct RowsPage: Sendable, Equatable {
    public let rows: [ListRow]
    public let hasMore: Bool
    public let nextOffset: Int?

    public init(rows: [ListRow], hasMore: Bool, nextOffset: Int?) {
        self.rows = rows
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// An empty page with no further results — used when a list has no rows.
    public static let empty = RowsPage(rows: [], hasMore: false, nextOffset: nil)
}
