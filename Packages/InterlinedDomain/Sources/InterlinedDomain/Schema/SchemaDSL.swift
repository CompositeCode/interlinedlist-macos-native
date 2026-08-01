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

    /// A `select` column declared an empty option list — `select()` or
    /// `select` with no options. A single-choice column needs at least one
    /// option to be meaningful. The field name is included for the toast.
    case emptySelectOptions(field: String)

    /// A `select` column repeated the same option — options must be a set so
    /// the picker never renders two identical rows. The offending option is
    /// included so the editor can highlight it.
    case duplicateSelectOption(field: String, option: String)
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
        case .emptySelectOptions(let field):
            return "Schema field \"\(field)\" is a select but declares no options."
        case .duplicateSelectOption(let field, let option):
            return "Schema field \"\(field)\" repeats the select option \"\(option)\"."
        }
    }
}

// MARK: - SchemaDSL

/// Parser and serializer for the InterlinedList schema DSL
/// (`"Title:text, Year:number, Released:date"`).
///
/// ## DSL grammar (M3 starter set + §1.1 select/markdown)
///
/// ```
/// schema       := field ( "," field )*
/// field        := name ":" type [ "(" options ")" ]
/// name         := one-or-more characters, no comma, no colon, trimmed
/// type         := one of the SchemaFieldType DSL tokens
/// options      := option ( "|" option )*          -- select only
/// option       := one-or-more characters, no pipe, no parens, trimmed
/// ```
///
/// The optional `"(" options ")"` suffix applies to `select` only
/// (`Priority:select(low|med|high)`). The option list is `|`-delimited so it
/// carries no top-level commas — the plain comma split still separates
/// fields. Empty option lists (`select()`) and duplicate options are typed
/// errors (`.emptySelectOptions` / `.duplicateSelectOption`). Non-`select`
/// types reject a trailing `(...)` as a syntax error. `markdown` parses like
/// `text` (no options).
///
/// The `select(...)` option grammar is a **client convention** — the API
/// documents the `markdown` token but not `select`'s option syntax (see
/// `SchemaFieldType.select`). It round-trips only through this file, so it is
/// the one place to adjust if the server pins a different token/delimiter.
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
            let typeSpec = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !typeSpec.isEmpty else {
                throw SchemaDSLError.invalidFieldSyntax(rawField: token)
            }

            // Split the type spec into its bare token and an optional
            // `(...)` option suffix. `select(low|med|high)` → ("select",
            // "low|med|high"); a bare `text` → ("text", nil).
            let (typeToken, optionsBody) = try Self.splitTypeSpec(typeSpec, rawField: token)

            guard let type = SchemaFieldType(dslToken: typeToken) else {
                throw SchemaDSLError.unknownType(rawType: typeToken)
            }

            // Option suffixes are only valid for option-carrying types
            // (`select`). A trailing `(...)` on any other type is a syntax
            // error so `text(a|b)` does not silently drop the options.
            let enumValues = try Self.resolveOptions(
                optionsBody,
                for: type,
                fieldName: name,
                rawField: token
            )

            // Duplicate-name check is case-sensitive — column names are
            // case-sensitive at the row-data layer too.
            guard !seenNames.contains(name) else {
                throw SchemaDSLError.duplicateFieldName(name)
            }
            seenNames.insert(name)
            fields.append(SchemaField(name: name, type: type, enumValues: enumValues))
        }

        return ListSchema(fields: fields)
    }

    // MARK: Type-spec + options parsing

    /// Splits a type spec into its bare token and optional `(...)` body.
    ///
    /// `"select(low|med|high)"` → `("select", "low|med|high")`;
    /// `"text"` → `("text", nil)`. A `(` with no matching trailing `)`,
    /// or trailing characters after the `)`, is a syntax error.
    private static func splitTypeSpec(
        _ spec: String,
        rawField: String
    ) throws -> (token: String, optionsBody: String?) {
        guard let openIndex = spec.firstIndex(of: "(") else {
            // No paren group: the whole spec is the type token. A stray
            // closing paren with no opener is malformed.
            guard !spec.contains(")") else {
                throw SchemaDSLError.invalidFieldSyntax(rawField: rawField)
            }
            return (spec, nil)
        }
        // Must close with `)` as the final character, with nothing after it.
        guard spec.hasSuffix(")") else {
            throw SchemaDSLError.invalidFieldSyntax(rawField: rawField)
        }
        let token = String(spec[spec.startIndex..<openIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyStart = spec.index(after: openIndex)
        let bodyEnd = spec.index(before: spec.endIndex) // the trailing `)`
        let body = String(spec[bodyStart..<bodyEnd])
        guard !token.isEmpty else {
            throw SchemaDSLError.invalidFieldSyntax(rawField: rawField)
        }
        return (token, body)
    }

    /// Validates and normalises a `select` option body, or asserts that
    /// non-option types carry no `(...)` suffix.
    ///
    /// - Returns: the ordered option array for `select`; `nil` otherwise.
    private static func resolveOptions(
        _ body: String?,
        for type: SchemaFieldType,
        fieldName: String,
        rawField: String
    ) throws -> [String]? {
        guard type.carriesOptions else {
            // A `(...)` suffix on a non-option type is a syntax error.
            if body != nil {
                throw SchemaDSLError.invalidFieldSyntax(rawField: rawField)
            }
            return nil
        }
        // `select` requires a `(...)` body with at least one option.
        guard let body else {
            throw SchemaDSLError.emptySelectOptions(field: fieldName)
        }
        let options = body
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Reject empty option lists and any blank option (e.g. `a||b`).
        guard !options.isEmpty, !options.contains(where: \.isEmpty) else {
            throw SchemaDSLError.emptySelectOptions(field: fieldName)
        }
        var seen: Set<String> = []
        for option in options where !seen.insert(option).inserted {
            throw SchemaDSLError.duplicateSelectOption(field: fieldName, option: option)
        }
        return options
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
            .map { field in
                let base = "\(field.name):\(field.type.dslToken)"
                // `select` re-emits its ordered option set inline. A select
                // with no options is a malformed in-memory value the editor
                // should never produce; guard defensively by omitting the
                // `()` so a reparse fails loudly rather than silently.
                guard field.type.carriesOptions,
                      let options = field.enumValues, !options.isEmpty else {
                    return base
                }
                return "\(base)(\(options.joined(separator: "|")))"
            }
            .joined(separator: ", ")
    }
}
