// AIDocumentSheetModeTests
//
// BDD tests for the AI document sheet's mode gate (work-consolidation.md G15).
//
// Each mode needs a different second input, and a mode that reaches the service
// without it fails server-side *after* spending a quota unit against the user's
// own provider key. The gate is what keeps that from happening, so it is tested
// as logic rather than left to the view.

import XCTest
import InterlinedDomain
@testable import InterlinedList

final class AIDocumentSheetModeTests: XCTestCase {

    private typealias Mode = AIDocumentSheet.Mode

    // MARK: - Happy path

    func test_givenArticleMode_whenResolved_thenNeedsNoSecondInput() {
        XCTAssertEqual(Mode.article.domainMode(listID: nil, documentID: nil, urlText: ""), .article)
        XCTAssertTrue(Mode.article.requiresPrompt)
    }

    func test_givenSelectedList_whenResolved_thenCarriesTheListId() {
        XCTAssertEqual(
            Mode.fromList.domainMode(listID: "l-1", documentID: nil, urlText: ""),
            .fromList(listId: "l-1")
        )
    }

    func test_givenSelectedDocument_whenResolved_thenCarriesTheDocumentId() {
        XCTAssertEqual(
            Mode.fromArticle.domainMode(listID: nil, documentID: "d-1", urlText: ""),
            .fromArticle(documentId: "d-1")
        )
    }

    func test_givenValidURL_whenResolved_thenCarriesTheURL() {
        let mode = Mode.researchURL.domainMode(
            listID: nil, documentID: nil, urlText: "  https://example.com/article  "
        )
        XCTAssertEqual(mode, .researchURL(URL(string: "https://example.com/article")!))
    }

    // MARK: - Invalid input

    func test_givenNoSelection_whenDerivedModesResolved_thenGateHolds() {
        XCTAssertNil(Mode.fromList.domainMode(listID: nil, documentID: "d", urlText: ""))
        XCTAssertNil(Mode.fromArticle.domainMode(listID: "l", documentID: nil, urlText: ""))
    }

    func test_givenUnusableURLs_whenResolved_thenGateHolds() {
        for text in ["", "   ", "not a url", "example.com", "/relative/path", "mailto:someone"] {
            XCTAssertNil(
                Mode.researchURL.domainMode(listID: nil, documentID: nil, urlText: text),
                "\"\(text)\" should not pass the URL gate"
            )
        }
    }

    // MARK: - Boundary

    func test_givenDerivedModes_whenChecked_thenPromptIsOptional() {
        // Only a standalone article needs the prompt; the others have a source.
        XCTAssertFalse(Mode.fromList.requiresPrompt)
        XCTAssertFalse(Mode.fromArticle.requiresPrompt)
        XCTAssertFalse(Mode.researchURL.requiresPrompt)
    }

    func test_givenEveryMode_whenLabelled_thenLabelsAreDistinct() {
        let labels = Mode.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertEqual(Set(Mode.allCases.map(\.promptHint)).count, Mode.allCases.count)
    }
}
