import Foundation

/// The closed set of column types the InterlinedList schema DSL recognises
/// (PLAN.md §1 "Structured lists", §6 M3).
///
/// The schema DSL is documented by example only (`"Title:text, Year:number"`)
/// and the API team has not yet enumerated the full type taxonomy
/// (see `/API-backend-prompts-to-build.md` item 2.2 — "Document schema DSL
/// field types and validation rules"). M3 picks a deliberately conservative
/// starter set drawn from PLAN.md and the prompts file; additional types
/// (e.g. `enum(...)`, `link(listSlug)`) are explicitly held back until the
/// upstream docs land.
///
/// The set below mirrors the six types that appear in the InterlinedList
/// schema-editor design and the M3 brief; any new type lands here in one
/// place so view code switching on `SchemaFieldType` stays exhaustive.
public enum SchemaFieldType: String, Sendable, Equatable, Hashable, CaseIterable {

    /// Free-form text. Wire shape: JSON string.
    case text

    /// Numeric value (integer or decimal — the API has not yet pinned this
    /// down per prompts file 2.2). Wire shape: JSON number.
    case number

    /// `true` / `false`. Wire shape: JSON boolean.
    case boolean

    /// An ISO-8601 date (date-only or datetime — the API has not yet pinned
    /// this down). Wire shape: JSON string.
    case date

    /// A URL. Wire shape: JSON string; server-side validation status not yet
    /// documented (prompts file 2.2).
    case url

    /// An email address. Wire shape: JSON string; server-side validation
    /// status not yet documented (prompts file 2.2).
    case email

    /// The canonical DSL token for this type ("text", "number", …). The
    /// raw value is the wire token by construction; this alias exists so
    /// the parser/serializer can read as intent rather than implementation.
    public var dslToken: String { rawValue }

    /// Maps a DSL token to a type, case-insensitively. Returns `nil` for any
    /// token outside the closed set — the parser surfaces that as
    /// `SchemaDSLError.unknownType`.
    public init?(dslToken: String) {
        self.init(rawValue: dslToken.lowercased())
    }
}
