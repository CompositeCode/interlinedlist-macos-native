import Foundation

/// Renders domain models to Markdown for the "Markdown export" data-portability
/// feature advertised on interlinedlist.com (feature-gaps.md §1.3 — "Markdown
/// export for lists, documents, and message threads with structured table
/// conversion").
///
/// **Why this is a client-side renderer.** The `/api/exports/*` endpoints return
/// CSV only — there is no Markdown format on the wire and no per-document /
/// per-thread export endpoint (see `feature-blockages.md` BE-1). So the app
/// composes Markdown itself from already-fetched domain models. This type is the
/// reusable engine every entry point calls; it is a pure value transformer with
/// no I/O, so it is exhaustively unit-testable and free of `Date.now`-style
/// nondeterminism (callers pass the dates that are already on the models).
///
/// The three surfaces mirror the three things the web app can export:
///   - `markdown(for:)`               — a single long-form document
///   - `markdown(forThreadRoot:replies:)` — a message and its replies
///   - `markdown(forList:)`           — a structured list as a Markdown table
public struct MarkdownExporter: Sendable {

    public init() {}

    /// ISO-8601 timestamps keep the output stable and locale-independent, which
    /// matters for deterministic tests and for diffable exports. Uses the
    /// value-type `ISO8601FormatStyle` (GMT, internet date-time) rather than a
    /// stored `ISO8601DateFormatter` — the latter is a non-`Sendable` reference
    /// type and cannot live inside this `Sendable` struct.
    private func timestamp(_ date: Date) -> String {
        date.ISO8601Format()
    }

    // MARK: - Documents

    /// Renders a long-form document as Markdown: an H1 title followed by the
    /// document body (which is already Markdown source). The body is emitted
    /// verbatim — documents author Markdown directly, so no escaping is applied.
    public func markdown(for document: Document) -> String {
        var out = "# \(document.title.isEmpty ? "Untitled" : document.title)\n"
        let body = document.body.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            out += "\n\(body)\n"
        }
        return out
    }

    // MARK: - Threads

    /// Renders a message thread: the root post, then its replies in ascending
    /// creation order as block quotes. Replies are rendered flat (sorted by
    /// `createdAt`) rather than nested by `parentID`; deep-nesting is a later
    /// refinement noted in feature-gaps.md.
    public func markdown(forThreadRoot root: Message, replies: [Message]) -> String {
        var out = "# Thread\n\n"
        out += renderPost(root)

        let ordered = replies.sorted { $0.createdAt < $1.createdAt }
        if !ordered.isEmpty {
            out += "\n---\n\n## Replies\n\n"
            for reply in ordered {
                out += renderReply(reply)
            }
        }
        return out
    }

    /// The root post: bold author handle + timestamp header, then the body.
    private func renderPost(_ message: Message) -> String {
        var block = "**@\(message.author.username)** · \(timestamp(message.createdAt))\n\n"
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            block += "\(text)\n"
        }
        return block
    }

    /// A reply, rendered as a Markdown block quote so nesting reads visually.
    private func renderReply(_ message: Message) -> String {
        let header = "> **@\(message.author.username)** · \(timestamp(message.createdAt))"
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotedBody = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        if text.isEmpty {
            return "\(header)\n\n"
        }
        return "\(header)\n>\n\(quotedBody)\n\n"
    }

    // MARK: - Lists (structured table conversion)

    /// Input bundle for a list export. Decoupled from `ListDetail` / `OwnedList`
    /// so both public and owned lists render through the same path.
    public struct ListInput: Sendable, Equatable {
        public let title: String
        public let description: String?
        /// The schema DSL string (e.g. `"Title:text, Year:number"`). Used only
        /// to derive the canonical column order; parsing beyond the field names
        /// is intentionally avoided so this renderer does not couple to the
        /// `SchemaDSL` grammar.
        public let schemaDSL: String?
        public let rows: [ListRow]

        public init(title: String, description: String?, schemaDSL: String?, rows: [ListRow]) {
            self.title = title
            self.description = description
            self.schemaDSL = schemaDSL
            self.rows = rows
        }
    }

    /// Renders a single list as a Markdown table ("structured table
    /// conversion"): an H1 title, optional italic description, then a table
    /// whose columns come from the schema (falling back to the union of row
    /// keys). Cell values are pipe- and newline-escaped so the table never
    /// breaks. A list with no derivable columns renders an explanatory line
    /// instead of an empty table.
    public func markdown(forList list: ListInput) -> String {
        var out = "# \(list.title.isEmpty ? "Untitled list" : list.title)\n"
        if let description = list.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            out += "\n_\(description)_\n"
        }

        let columns = Self.columns(fromSchemaDSL: list.schemaDSL, rows: list.rows)
        guard !columns.isEmpty else {
            out += "\n_No columns defined._\n"
            return out
        }

        out += "\n"
        out += "| " + columns.map(Self.escapeCell).joined(separator: " | ") + " |\n"
        out += "| " + columns.map { _ in "---" }.joined(separator: " | ") + " |\n"

        if list.rows.isEmpty {
            // A header with no data rows is still valid Markdown; keep the table
            // shape and let the empty body speak for itself.
            return out
        }

        for row in list.rows {
            let cells = columns.map { column -> String in
                Self.escapeCell(row.fields[column]?.displayText ?? "")
            }
            out += "| " + cells.joined(separator: " | ") + " |\n"
        }
        return out
    }

    /// Concatenates several lists into one Markdown document, separated by a
    /// horizontal rule. Used by the "Export all my lists" flow.
    public func markdown(forLists lists: [ListInput]) -> String {
        lists.map { markdown(forList: $0) }.joined(separator: "\n---\n\n")
    }

    // MARK: - Helpers

    /// Derives the ordered column set for a list table. Prefers the declared
    /// schema (parsed just far enough to read the field *names*, left-of-colon);
    /// falls back to the sorted union of keys observed across the rows so a
    /// schemaless list still exports something sensible.
    static func columns(fromSchemaDSL dsl: String?, rows: [ListRow]) -> [String] {
        if let dsl {
            let names = dsl
                .split(separator: ",")
                .compactMap { pair -> String? in
                    let name = pair.split(separator: ":", maxSplits: 1).first
                        .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                    return name.isEmpty ? nil : name
                }
            if !names.isEmpty {
                return names
            }
        }
        var seen = Set<String>()
        var ordered: [String] = []
        for row in rows {
            for key in row.fields.keys.sorted() where !seen.contains(key) {
                seen.insert(key)
                ordered.append(key)
            }
        }
        return ordered
    }

    /// Escapes a value for a Markdown table cell: pipes are backslash-escaped
    /// and newlines collapse to spaces so a multi-line value cannot split the
    /// row across table lines.
    static func escapeCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
