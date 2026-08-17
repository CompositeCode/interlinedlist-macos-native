// MarkdownExportRequestTests
//
// BDD-named tests for `MarkdownExportRequest.filenameStem(from:fallback:)`,
// the shared save-panel filename sanitiser used by the per-document and
// per-thread Markdown export entry points (work-consolidation.md §1b).

import XCTest
@testable import InterlinedList

final class MarkdownExportRequestTests: XCTestCase {

    func test_givenTitleWithSpacesAndPunctuation_whenStem_thenLowercasedHyphenated() {
        let stem = MarkdownExportRequest.filenameStem(from: "My Great Doc!", fallback: "document")
        XCTAssertEqual(stem, "my-great-doc")
    }

    func test_givenLeadingAndTrailingSymbols_whenStem_thenTrimmed() {
        let stem = MarkdownExportRequest.filenameStem(from: "  Hello, World!!  ", fallback: "x")
        XCTAssertEqual(stem, "hello-world")
    }

    func test_givenRunsOfSeparators_whenStem_thenCollapsedToSingleHyphen() {
        let stem = MarkdownExportRequest.filenameStem(from: "a  --  b__c", fallback: "x")
        XCTAssertEqual(stem, "a-b-c")
    }

    func test_givenDigits_whenStem_thenPreserved() {
        let stem = MarkdownExportRequest.filenameStem(from: "Q3 2026 Plan", fallback: "x")
        XCTAssertEqual(stem, "q3-2026-plan")
    }

    func test_givenSymbolOnlyTitle_whenStem_thenReturnsFallback() {
        let stem = MarkdownExportRequest.filenameStem(from: "***", fallback: "document")
        XCTAssertEqual(stem, "document")
    }

    func test_givenEmptyTitle_whenStem_thenReturnsFallback() {
        let stem = MarkdownExportRequest.filenameStem(from: "", fallback: "thread")
        XCTAssertEqual(stem, "thread")
    }
}
