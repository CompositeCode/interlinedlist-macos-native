import XCTest
@testable import InterlinedDomain

/// BDD coverage for `MessagePermalink` (GitHub #27 — the "Link" message
/// action). The builder is pure and synchronous, so the quartet is
/// happy / invalid / upstream-shape / boundary with no service doubles.
final class MessagePermalinkTests: XCTestCase {

    // MARK: - Happy path

    func test_givenWellFormedID_whenBuildingPermalink_thenUsesMessagesRoute() {
        // Given a normal server-issued id.
        let id = "cmg1a2b3c4d5"

        // When we build the permalink against the production base.
        let url = MessagePermalink.url(forMessageID: id)

        // Then it matches the web app's own /messages/<id> route.
        XCTAssertEqual(url?.absoluteString, "https://interlinedlist.com/messages/cmg1a2b3c4d5")
    }

    func test_givenMessage_whenAskedForPermalink_thenMatchesBuilder() {
        // Given a domain message.
        let message = Self.makeMessage(id: "abc123")

        // When we ask the message itself.
        let fromMessage = message.permalink()

        // Then it agrees with the standalone builder — one definition, not two.
        XCTAssertEqual(fromMessage, MessagePermalink.url(forMessageID: "abc123"))
    }

    // MARK: - Invalid input

    func test_givenEmptyID_whenBuildingPermalink_thenReturnsNil() {
        // Given an empty id (a message that never round-tripped the server).
        // When / Then — no half-formed URL is produced; the UI hides the action.
        XCTAssertNil(MessagePermalink.url(forMessageID: ""))
    }

    func test_givenWhitespaceOnlyID_whenBuildingPermalink_thenReturnsNil() {
        // Given an id that is only whitespace.
        // When / Then — treated the same as empty rather than linking to /messages/%20.
        XCTAssertNil(MessagePermalink.url(forMessageID: "   \n  "))
    }

    // MARK: - Upstream shape (caller-supplied base)

    func test_givenBaseWithTrailingSlash_whenBuildingPermalink_thenNoDoubleSlash() {
        // Given a base URL a caller wrote with a trailing slash.
        let base = URL(string: "https://staging.interlinedlist.com/")!

        // When we build against it.
        let url = MessagePermalink.url(forMessageID: "xyz", base: base)

        // Then the path is normalised rather than containing "//messages".
        XCTAssertEqual(url?.absoluteString, "https://staging.interlinedlist.com/messages/xyz")
    }

    func test_givenBaseWithSubpath_whenBuildingPermalink_thenSubpathIsPreserved() {
        // Given a base that already carries a path prefix.
        let base = URL(string: "https://example.test/app")!

        // When we build against it.
        let url = MessagePermalink.url(forMessageID: "xyz", base: base)

        // Then the prefix survives — the builder appends, it does not replace.
        XCTAssertEqual(url?.absoluteString, "https://example.test/app/messages/xyz")
    }

    // MARK: - Boundary

    func test_givenIDNeedingPercentEncoding_whenBuildingPermalink_thenEncoded() {
        // Given an id carrying characters that are illegal in a path segment.
        let id = "a b#c"

        // When we build the permalink.
        let url = MessagePermalink.url(forMessageID: id)

        // Then they are percent-encoded rather than truncating the URL at the "#".
        XCTAssertEqual(url?.absoluteString, "https://interlinedlist.com/messages/a%20b%23c")
    }

    func test_givenIDContainingSlash_whenBuildingPermalink_thenSlashIsEncodedNotForged() {
        // Given a hostile / malformed id containing a path separator.
        let id = "abc/../admin"

        // When we build the permalink.
        let url = MessagePermalink.url(forMessageID: id)

        // Then the slashes are encoded — the id can never forge extra path
        // segments, so the link always points inside /messages/.
        XCTAssertEqual(url?.absoluteString, "https://interlinedlist.com/messages/abc%2F..%2Fadmin")
    }

    func test_givenIDWithSurroundingWhitespace_whenBuildingPermalink_thenTrimmed() {
        // Given an id padded by whitespace.
        // When / Then — trimmed, not encoded as %20 padding.
        XCTAssertEqual(
            MessagePermalink.url(forMessageID: "  abc  ")?.absoluteString,
            "https://interlinedlist.com/messages/abc"
        )
    }

    // MARK: - Helpers

    private static func makeMessage(id: String) -> Message {
        Message(
            id: id,
            author: UserSummary(id: "u1", username: "adron", displayName: "Adron"),
            text: "hello",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            visibility: .public,
            digCount: 0,
            didDig: false,
            repostCount: 0
        )
    }
}
