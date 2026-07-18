import XCTest
@testable import InterlinedDomain

/// BDD-named tests for the client-side document-template catalog
/// (feature-gaps.md §1.4). Pure value-type checks — the catalog is static and
/// dependency-free, so there is no service to stub.
final class DocumentTemplateTests: XCTestCase {

    // MARK: - Catalog shape

    func test_givenBuiltInCatalog_whenInspected_thenIsNonEmpty() {
        // Happy path: the picker always has something to show.
        XCTAssertFalse(DocumentTemplate.builtIn.isEmpty)
    }

    func test_givenBuiltInCatalog_whenInspected_thenIdsAreUnique() {
        let ids = DocumentTemplate.builtIn.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_givenBuiltInCatalog_whenInspected_thenNamesAndSummariesAreNonBlank() {
        // Boundary: no template ships with a blank name or summary — those are
        // the only two fields the picker renders as user-facing text.
        for template in DocumentTemplate.builtIn {
            XCTAssertFalse(
                template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "template \(template.id) has a blank name"
            )
            XCTAssertFalse(
                template.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "template \(template.id) has a blank summary"
            )
        }
    }

    // MARK: - Blank identity

    func test_givenBlankTemplate_whenInspected_thenSeedsEmptyBody() {
        // The blank path must be byte-for-byte the existing "new blank
        // document" behavior — an empty markdown body.
        XCTAssertEqual(DocumentTemplate.blank.bodyMarkdown, "")
        XCTAssertEqual(DocumentTemplate.blank.body, .empty)
    }

    func test_givenBuiltInCatalog_whenInspected_thenFirstEntryIsBlank() {
        // The picker leans on this ordering to keep "start from scratch" first.
        XCTAssertEqual(DocumentTemplate.builtIn.first?.id, DocumentTemplate.blank.id)
    }

    // MARK: - Named templates seed real content

    func test_givenNamedTemplate_whenInspected_thenSeedsNonEmptyMarkdown() {
        // Every non-blank template seeds real starter Markdown, and its typed
        // `body` matches its raw `bodyMarkdown`.
        let named = DocumentTemplate.builtIn.filter { $0.id != DocumentTemplate.blank.id }
        XCTAssertFalse(named.isEmpty, "expected at least one non-blank template")
        for template in named {
            XCTAssertFalse(
                template.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "template \(template.id) seeds no content"
            )
            XCTAssertEqual(template.body, DocumentBody(markdown: template.bodyMarkdown))
        }
    }

    func test_givenMeetingNotesTemplate_whenInspected_thenContainsExpectedSections() {
        // Named-template happy path: the Meeting Notes body carries its
        // signature Action Items section.
        let template = DocumentTemplate.meetingNotes
        XCTAssertTrue(template.bodyMarkdown.contains("# Meeting Notes"))
        XCTAssertTrue(template.bodyMarkdown.contains("## Action Items"))
    }
}
