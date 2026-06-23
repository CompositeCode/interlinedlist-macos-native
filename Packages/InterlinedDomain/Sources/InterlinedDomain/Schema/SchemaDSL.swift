import Foundation

// MARK: - SchemaDSLError

/// Typed errors surfaced by the schema DSL parser
/// (PLAN.md §1 "Structured lists", §6 M3, §7 testing — the parser is one of
/// the two places PLAN.md §7 calls out for the deepest test suite).
///
/// Errors are deliberately specific so the editor can surface a precise
/// message at the exact column that failed. The starter set is closed; new
/// validation rules (e.g. enum-value malformed, link-target invalid) extend
/// this enum, not the parser's switch logic.
public enum SchemaDSLError: Error, Sendable, Equatable {

    /// The DSL source was empty / whitespace-only. The editor never calls
    /// the parser with `""` (the empty schema is its own value
    /// `ListSchema.empty`), so this signals a programming error.
    case emptySource

    /// A field was not of the shape `"Name:type"`. The raw token is included
    /// for the error toast.
    case invalidFieldSyntax(rawField: String)

    /// The type token was outside the closed `SchemaFieldType` set. The raw
    /// type token is included so the editor can suggest a near match.
    case unknownType(rawType: String)

    /// Two columns share the same name — schemas forbid duplicates so the
    /// cell map (`[String: ListCellValue]`) stays unambiguous.
    case duplicateFieldName(String)
}

extension SchemaDSLError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .emptySource:
            return "Schema DSL source is empty."
        case .invalidFieldSyntax(let raw):
            return "Schema field \"\(raw)\" is not of the form \"Name:type\"."
        case .unknownType(let raw):
            return "Schema type \"\(raw)\" is not a recognised type."
        case .duplicateFieldName(let name):
            return "Schema field \"\(name)\" is declared more than once."
        }
    }
}

// MARK: - SchemaDSL

/// Parser and serializer for the InterlinedList schema DSL
/// (`"Title:text, Year:number, Released:date"`).
///
/// ## DSL grammar (M3 starter set — see prompts file item 2.2)
///
/// ```
/// schema       := field ( "," field )*
/// field        := name ":" type
/// name         := one-or-more characters, no comma, no colon, trimmed
/// type         := one of the SchemaFieldType DSL tokens
/// ```
///
/// Whitespace around commas and colons is tolerated (and stripped) on parse,
/// and re-emitted in canonical form by `serialize` so that `parse → serialize`
/// is **normalising** rather than verbatim. The round-trip guarantee is
/// `serialize(parse(serialize(x))) == serialize(parse(x))` — i.e. the
/// serializer's canonical output is idempotent through another parse.
///
/// Future DSL extensions (`enum(...)`, `link(listSlug)`, per-type modifiers
/// like `?` for nullable) are explicitly held back until the upstream
/// taxonomy lands (prompts file 2.2). When they arrive, they extend the
/// `name : type` grammar above — they do not change the comma-separated
/// list shape.
public enum SchemaDSL {

    // MARK: Parse

    /// Parses a DSL source string into a typed `ListSchema`.
    ///
    /// - Parameter source: the DSL string from the API (`ListSchemaDTO.schema`
    ///   or `ListDTO.schema`).
    /// - Returns: a parsed `ListSchema` preserving column order.
    /// - Throws: `SchemaDSLError` for any malformed input.
    public static func parse(_ source: String) throws -> ListSchema {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw SchemaDSLError.emptySource
        }

        // Split on commas at the top level. The starter grammar has no
        // nested commas (no `enum(a, b)` yet), so a plain split is correct.
        let rawFields = trimmedSource.split(separator: ",", omittingEmptySubsequences: false)

        var fields: [SchemaField] = []
        var seenNames: Set<String> = []

        for raw in rawFields {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // A trailing comma yields an empty token; treat that as a
            // syntax error so trailing-comma typos do not silently produce
            // a partial schema.
            guard !token.isEmpty else {
                throw SchemaDSLError.invalidFieldSyntax(rawField: String(raw))
            }

            let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw SchemaDSLError.invalidFieldSyntax(rawField: token)
            }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let typeToken = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !typeToken.isEmpty else {
                throw SchemaDSLError.invalidFieldSyntax(rawField: token)
            }
            guard let type = SchemaFieldType(dslToken: typeToken) else {
                throw SchemaDSLError.unknownType(rawType: typeToken)
            }
            // Duplicate-name check is case-sensitive — column names are
            // case-sensitive at the row-data layer too.
            guard !seenNames.contains(name) else {
                throw SchemaDSLError.duplicateFieldName(name)
            }
            seenNames.insert(name)
            fields.append(SchemaField(name: name, type: type))
        }

        return ListSchema(fields: fields)
    }

    // MARK: Serialize

    /// Serializes a `ListSchema` back to the canonical DSL form
    /// (`"Title:text, Year:number"`).
    ///
    /// The canonical form uses exactly `", "` (comma + single space) between
    /// fields and exactly `":"` (no spaces) between name and type. This
    /// matches the wire shape the editor will resend on save.
    ///
    /// An empty schema serializes to `""`. The parser rejects `""`, so a
    /// round-trip through `parse(serialize(empty))` throws `.emptySource`
    /// by design — `ListSchema.empty` is the in-memory representation; the
    /// wire never carries it.
    public static func serialize(_ schema: ListSchema) -> String {
        schema.fields
            .map { "\($0.name):\($0.type.dslToken)" }
            .joined(separator: ", ")
    }
}
