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

    /// A single-choice value drawn from an ordered option set carried by the
    /// owning `SchemaField.enumValues`. The DSL declares the options inline:
    /// `Priority:select(low|med|high)`. Wire shape (row data): JSON string —
    /// the chosen option's raw text. The option list itself lives in the
    /// schema DSL string, not in row data.
    ///
    /// The `select(...)` option-encoding grammar is a **client convention**
    /// introduced here: the API's `markdown` token is documented at
    /// interlinedlist.com/help/api/lists, but the `select` option syntax is
    /// not enumerated there (the docs note "a few others" exist without
    /// pinning the grammar). If the server names the token or delimiter
    /// differently, this is the single place that changes — see the
    /// serializer/parser in `SchemaDSL`.
    case select

    /// Long-form Markdown text. Parses like `text` (no options); rendered as
    /// an editable multiline field with a Markdown preview in the UI, reusing
    /// the same `Textual` renderer as Documents. Wire shape: JSON string
    /// carrying raw Markdown source. Documented token at
    /// interlinedlist.com/help/api/lists.
    case markdown

    /// The canonical DSL token for this type ("text", "number", …). The
    /// raw value is the wire token by construction; this alias exists so
    /// the parser/serializer can read as intent rather than implementation.
    ///
    /// Note this is the *bare* type token only. A `select` column emits its
    /// options separately (`select(a|b|c)`); the option list is not part of
    /// `dslToken` — see `SchemaDSL.serialize`.
    public var dslToken: String { rawValue }

    /// Whether this type carries an inline option set in the DSL
    /// (`type(a|b|c)`). Only `select` does today; centralised here so the
    /// parser, serializer, and editor all agree on which types need options.
    public var carriesOptions: Bool { self == .select }

    /// Maps a DSL token to a type, case-insensitively. Returns `nil` for any
    /// token outside the closed set — the parser surfaces that as
    /// `SchemaDSLError.unknownType`.
    public init?(dslToken: String) {
        self.init(rawValue: dslToken.lowercased())
    }
}
