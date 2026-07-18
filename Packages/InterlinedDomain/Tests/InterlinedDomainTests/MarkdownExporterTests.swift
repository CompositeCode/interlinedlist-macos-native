import XCTest
@testable import InterlinedDomain

/// BDD-named coverage for `MarkdownExporter` — the client-side Markdown
/// renderer that implements the "Markdown export for lists, documents, and
/// threads" parity feature (feature-gaps.md §1.3). The renderer is a pure
/// value transformer, so every surface is asserted structurally without any
/// network or clock dependency.
final class MarkdownExporterTests: XCTestCase {

    private let exporter = MarkdownExporter()

    // MARK: - Fixtures

    private func user(_ handle: String) -> UserSummary {
        UserSummary(id: "u-\(handle)", username: handle, displayName: handle.capitalized)
    }

    private func message(
        id: String,
        handle: String,
        text: String,
        at seconds: TimeInterval
    ) -> Message {
        Message(
            id: id,
            author: user(handle),
            text: text,
            createdAt: Date(timeIntervalSince1970: seconds),
            updatedAt: Date(timeIntervalSince1970: seconds),
            visibility: .public,
            digCount: 0,
            didDig: false,
            repostCount: 0
        )
    }

    private func row(_ id: String, _ fields: [String: ListCellValue]) -> ListRow {
        ListRow(id: id, listID: "L1", fields: fields)
    }

    // MARK: - Documents

    func test_givenDocumentWithTitleAndBody_whenRendered_thenEmitsHeadingThenBody() {
        // Given a long-form document whose body is already Markdown.
        let doc = Document(
            id: "d1",
            title: "Release Notes",
            body: DocumentBody(markdown: "## v1\n\n- Fixed things"),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        // When
        let md = exporter.markdown(for: doc)

        // Then — H1 title first, body preserved verbatim (not escaped).
        XCTAssertTrue(md.hasPrefix("# Release Notes\n"), "title heading missing: \(md)")
        XCTAssertTrue(md.contains("## v1"), "body markdown should pass through verbatim")
        XCTAssertTrue(md.contains("- Fixed things"))
    }

    func test_givenDocumentWithEmptyTitle_whenRendered_thenUsesUntitled() {
        let doc = Document(id: "d1", title: "", updatedAt: Date(timeIntervalSince1970: 0))
        let md = exporter.markdown(for: doc)
        XCTAssertTrue(md.hasPrefix("# Untitled\n"), "empty title should fall back to Untitled: \(md)")
    }

    func test_givenDocumentWithEmptyBody_whenRendered_thenOnlyHeadingRemains() {
        let doc = Document(id: "d1", title: "Empty", body: .empty, updatedAt: Date(timeIntervalSince1970: 0))
        let md = exporter.markdown(for: doc)
        XCTAssertEqual(md, "# Empty\n", "an empty body should leave just the heading")
    }

    // MARK: - Threads

    func test_givenThreadRootOnly_whenRendered_thenNoRepliesSection() {
        // Given a root post with no replies.
        let root = message(id: "m1", handle: "alice", text: "Original post", at: 100)

        // When
        let md = exporter.markdown(forThreadRoot: root, replies: [])

        // Then
        XCTAssertTrue(md.contains("# Thread"))
        XCTAssertTrue(md.contains("**@alice**"), "author handle should be bolded")
        XCTAssertTrue(md.contains("Original post"))
        XCTAssertFalse(md.contains("## Replies"), "no replies section when there are no replies")
    }

    func test_givenRepliesOutOfOrder_whenRendered_thenSortedByCreatedAtAscending() {
        // Given the root and two replies passed newest-first.
        let root = message(id: "m1", handle: "alice", text: "Root", at: 100)
        let late = message(id: "m3", handle: "carol", text: "LATE_REPLY", at: 300)
        let early = message(id: "m2", handle: "bob", text: "EARLY_REPLY", at: 200)

        // When — deliberately pass out of chronological order.
        let md = exporter.markdown(forThreadRoot: root, replies: [late, early])

        // Then — replies section exists and the earlier reply renders first.
        XCTAssertTrue(md.contains("## Replies"))
        let earlyIdx = try? XCTUnwrap(md.range(of: "EARLY_REPLY")).lowerBound
        let lateIdx = try? XCTUnwrap(md.range(of: "LATE_REPLY")).lowerBound
        XCTAssertNotNil(earlyIdx); XCTAssertNotNil(lateIdx)
        if let earlyIdx, let lateIdx {
            XCTAssertLessThan(earlyIdx, lateIdx, "earlier reply must render before the later one")
        }
        // Replies render as block quotes.
        XCTAssertTrue(md.contains("> EARLY_REPLY"), "reply body should be quoted")
    }

    // MARK: - Lists (table conversion)

    func test_givenSchemaDSL_whenRenderingList_thenColumnsFollowSchemaOrder() {
        // Given a list whose schema declares Title before Year.
        let input = MarkdownExporter.ListInput(
            title: "Films",
            description: "Sci-fi",
            schemaDSL: "Title:text, Year:number",
            rows: [row("r1", ["Title": .string("Dune"), "Year": .int(1965)])]
        )

        // When
        let md = exporter.markdown(forList: input)

        // Then — heading, italic description, schema-ordered header + separator + row.
        XCTAssertTrue(md.contains("# Films"))
        XCTAssertTrue(md.contains("_Sci-fi_"), "description should render italic")
        XCTAssertTrue(md.contains("| Title | Year |"), "columns follow schema order: \(md)")
        XCTAssertTrue(md.contains("| --- | --- |"))
        XCTAssertTrue(md.contains("| Dune | 1965 |"))
    }

    func test_givenNoSchema_whenRenderingList_thenColumnsAreSortedUnionOfRowKeys() {
        // Given no schema — columns must be derived from the rows.
        let input = MarkdownExporter.ListInput(
            title: "Ad hoc",
            description: nil,
            schemaDSL: nil,
            rows: [
                row("r1", ["b": .string("2"), "a": .string("1")]),
                row("r2", ["c": .string("3")])
            ]
        )

        // When
        let md = exporter.markdown(forList: input)

        // Then — union of keys, deterministically sorted: a, b, c.
        XCTAssertTrue(md.contains("| a | b | c |"), "fallback columns should be sorted union: \(md)")
    }

    func test_givenCellWithPipeAndNewline_whenRenderingList_thenValueIsEscaped() {
        // Given a value containing a pipe and a newline that would break a table.
        let input = MarkdownExporter.ListInput(
            title: "Escapes",
            description: nil,
            schemaDSL: "Note:text",
            rows: [row("r1", ["Note": .string("a|b\nc")])]
        )

        // When
        let md = exporter.markdown(forList: input)

        // Then — pipe backslash-escaped, newline collapsed to a space.
        XCTAssertTrue(md.contains("| a\\|b c |"), "cell should be pipe-escaped and newline-collapsed: \(md)")
    }

    func test_givenEmptyRows_whenRenderingList_thenHeaderOnlyTable() {
        let input = MarkdownExporter.ListInput(
            title: "Empty",
            description: nil,
            schemaDSL: "Title:text",
            rows: []
        )
        let md = exporter.markdown(forList: input)
        XCTAssertTrue(md.contains("| Title |"))
        XCTAssertTrue(md.contains("| --- |"))
        // No data rows beyond the header + separator.
        let dataLines = md.split(separator: "\n").filter { $0.hasPrefix("|") }
        XCTAssertEqual(dataLines.count, 2, "header + separator only, no data rows")
    }

    func test_givenNoColumnsDerivable_whenRenderingList_thenExplanatoryLine() {
        let input = MarkdownExporter.ListInput(
            title: "Barren",
            description: nil,
            schemaDSL: nil,
            rows: []
        )
        let md = exporter.markdown(forList: input)
        XCTAssertTrue(md.contains("_No columns defined._"), "empty list should explain, not render an empty table")
        XCTAssertFalse(md.contains("| --- |"))
    }

    func test_givenMultipleLists_whenRendered_thenSeparatedByHorizontalRule() {
        let a = MarkdownExporter.ListInput(title: "A", description: nil, schemaDSL: "X:text", rows: [])
        let b = MarkdownExporter.ListInput(title: "B", description: nil, schemaDSL: "Y:text", rows: [])
        let md = exporter.markdown(forLists: [a, b])
        XCTAssertTrue(md.contains("# A"))
        XCTAssertTrue(md.contains("# B"))
        XCTAssertTrue(md.contains("\n---\n"), "lists should be separated by a horizontal rule")
    }

    // MARK: - Helpers (columns / escaping)

    func test_givenSchemaWithWhitespaceAndBareNames_whenParsingColumns_thenTrimmedNamesInOrder() {
        // Given a messy DSL (extra spaces, a bare name with no type).
        let cols = MarkdownExporter.columns(fromSchemaDSL: "  First : text ,  Second ,Third:number", rows: [])
        XCTAssertEqual(cols, ["First", "Second", "Third"], "names trimmed, types ignored, order preserved")
    }

    func test_givenEmptySchemaString_whenParsingColumns_thenFallsBackToRowKeys() {
        let rows = [row("r1", ["k": .string("v")])]
        let cols = MarkdownExporter.columns(fromSchemaDSL: "", rows: rows)
        XCTAssertEqual(cols, ["k"], "an empty schema string must fall back to row keys")
    }

    func test_givenBackslashAndPipe_whenEscapingCell_thenBothEscaped() {
        XCTAssertEqual(MarkdownExporter.escapeCell("a\\b|c"), "a\\\\b\\|c")
    }
}
