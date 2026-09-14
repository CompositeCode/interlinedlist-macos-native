import XCTest
@testable import InterlinedDomain

/// BDD coverage for `MessagePermalink` (GitHub #38 — the public permalink and
/// the "Get embed code" snippet behind the row's Share menu; originally added
/// for #27 against the wrong `/messages/<id>` route).
///
/// The builder is pure and synchronous, so the quartet is
/// happy / invalid / no-public-surface / boundary with no service doubles. The
/// "upstream failure" slot has no meaning for a projection with no I/O; per the
/// issue it is spent instead on the case that actually bites — a private
/// message must offer no link and no embed at all.
final class MessagePermalinkTests: XCTestCase {

    // MARK: - Happy path

    func test_givenPublicMessage_whenBuildingPermalink_thenUsesPublicUserStatusRoute() {
        // Given a normal server-issued id and author handle.
        // When we build the permalink against the production base.
        let url = MessagePermalink.url(forMessageID: "cmg1a2b3c4d5", authorUsername: "hubcity")

        // Then it is the route that serves a signed-out visitor, verified live:
        // /user/<handle>/status/<id> answers 200 while /messages/<id> redirects
        // to /login.
        XCTAssertEqual(
            url?.absoluteString,
            "https://interlinedlist.com/user/hubcity/status/cmg1a2b3c4d5"
        )
    }

    func test_givenPublicMessage_whenAskedForPermalink_thenMatchesBuilder() {
        // Given a public domain message.
        let message = Self.makeMessage(id: "abc123", username: "ada")

        // When we ask the message itself.
        let fromMessage = message.permalink()

        // Then it agrees with the standalone builder — one definition, not two.
        XCTAssertEqual(
            fromMessage,
            MessagePermalink.url(forMessageID: "abc123", authorUsername: "ada")
        )
        XCTAssertEqual(
            fromMessage?.absoluteString,
            "https://interlinedlist.com/user/ada/status/abc123"
        )
    }

    func test_givenPublicMessage_whenBuildingEmbedHTML_thenMatchesTheWebSnippetVerbatim() {
        // Given the same message the web would embed.
        // When we build the embed code.
        let html = MessagePermalink.embedHTML(forMessageID: "abc123", authorUsername: "ada")

        // Then it is the web's own snippet, character for character: the
        // il-embed blockquote carrying the raw id, the no-script fallback
        // anchor, and the async widgets loader.
        XCTAssertEqual(html, """
        <blockquote class="il-embed" data-message-id="abc123">
          <a href="https://interlinedlist.com/user/ada/status/abc123" target="_blank" rel="noopener">View this message on InterlinedList</a>
        </blockquote>
        <script async src="https://interlinedlist.com/embed/widgets.js"></script>
        """)
    }

    func test_givenPublicMessage_whenAskedForEmbedHTML_thenMatchesBuilder() {
        // Given a public domain message.
        let message = Self.makeMessage(id: "abc123", username: "ada")

        // When / Then — the convenience mirrors the builder rather than
        // re-deriving the markup.
        XCTAssertEqual(
            message.embedHTML(),
            MessagePermalink.embedHTML(forMessageID: "abc123", authorUsername: "ada")
        )
    }

    // MARK: - Invalid input

    func test_givenEmptyID_whenBuildingPermalink_thenReturnsNil() {
        // Given an empty id (a message that never round-tripped the server).
        // When / Then — no half-formed URL is produced; the UI hides the action.
        XCTAssertNil(MessagePermalink.url(forMessageID: "", authorUsername: "ada"))
        XCTAssertNil(MessagePermalink.embedHTML(forMessageID: "", authorUsername: "ada"))
    }

    func test_givenWhitespaceOnlyID_whenBuildingPermalink_thenReturnsNil() {
        // Given an id that is only whitespace.
        // When / Then — treated the same as empty rather than linking to a
        // /status/%20 route that 404s.
        XCTAssertNil(MessagePermalink.url(forMessageID: "   \n  ", authorUsername: "ada"))
    }

    func test_givenMissingAuthorHandle_whenBuildingPermalink_thenReturnsNil() {
        // Given a message projection that dropped the author handle.
        // When / Then — the public route needs the handle, so there is no link
        // to offer and the affordance is hidden rather than broken.
        XCTAssertNil(MessagePermalink.url(forMessageID: "abc123", authorUsername: ""))
        XCTAssertNil(MessagePermalink.embedHTML(forMessageID: "abc123", authorUsername: ""))
    }

    func test_givenBlankAuthorHandle_whenBuildingPermalink_thenReturnsNil() {
        // Given a whitespace-only handle.
        // When / Then — same as missing.
        XCTAssertNil(MessagePermalink.url(forMessageID: "abc123", authorUsername: " \t "))
    }

    // MARK: - No public surface (the "upstream failure" slot for a pure projection)

    func test_givenPrivateMessage_whenAskedForPermalink_thenOffersNoLink() {
        // Given a private message.
        let message = Self.makeMessage(id: "abc123", username: "ada", visibility: .private)

        // When / Then — only public messages resolve for a signed-out reader,
        // so the row offers no Link action at all rather than copying a URL
        // that shows the recipient nothing.
        XCTAssertNil(message.permalink())
    }

    func test_givenPrivateMessage_whenAskedForEmbedHTML_thenOffersNoEmbed() {
        // Given the same private message.
        let message = Self.makeMessage(id: "abc123", username: "ada", visibility: .private)

        // When / Then — an embed of a private post renders nothing for a
        // visitor, so the action is withheld too.
        XCTAssertNil(message.embedHTML())
    }

    func test_givenPrivateMessage_whenBuildingViaRawBuilder_thenStillBuilds() {
        // Given the raw builder, which knows ids and handles but not privacy.
        // When / Then — the visibility rule lives on `Message`, keeping the
        // builder a pure string projection the owner's own surfaces can reuse.
        XCTAssertNotNil(MessagePermalink.url(forMessageID: "abc123", authorUsername: "ada"))
    }

    // MARK: - Caller-supplied base

    func test_givenBaseWithTrailingSlash_whenBuildingPermalink_thenNoDoubleSlash() {
        // Given a base URL a caller wrote with a trailing slash.
        let base = URL(string: "https://staging.interlinedlist.com/")!

        // When we build against it.
        let url = MessagePermalink.url(forMessageID: "xyz", authorUsername: "ada", base: base)

        // Then the path is normalised rather than containing "//user".
        XCTAssertEqual(url?.absoluteString, "https://staging.interlinedlist.com/user/ada/status/xyz")
    }

    func test_givenBaseWithTrailingSlash_whenBuildingEmbedHTML_thenScriptSrcIsNormalised() {
        // Given the same trailing-slash base.
        let base = URL(string: "https://staging.interlinedlist.com/")!

        // When we build the embed code.
        let html = MessagePermalink.embedHTML(forMessageID: "xyz", authorUsername: "ada", base: base)

        // Then the widgets loader is not requested from a doubled slash — the
        // web strips trailing slashes from the origin the same way.
        XCTAssertEqual(html?.contains(#"src="https://staging.interlinedlist.com/embed/widgets.js""#), true)
    }

    func test_givenBaseWithSubpath_whenBuildingPermalink_thenSubpathIsPreserved() {
        // Given a base that already carries a path prefix.
        let base = URL(string: "https://example.test/app")!

        // When we build against it.
        let url = MessagePermalink.url(forMessageID: "xyz", authorUsername: "ada", base: base)

        // Then the prefix survives — the builder appends, it does not replace.
        XCTAssertEqual(url?.absoluteString, "https://example.test/app/user/ada/status/xyz")
    }

    // MARK: - Boundary

    func test_givenHandleAndIDNeedingPercentEncoding_whenBuildingPermalink_thenBothEncoded() {
        // Given a handle and an id carrying characters illegal in a path segment.
        // When we build the permalink.
        let url = MessagePermalink.url(forMessageID: "a b#c", authorUsername: "adá x")

        // Then both segments are percent-encoded rather than truncating the URL
        // at the "#" or breaking on the space.
        XCTAssertEqual(
            url?.absoluteString,
            "https://interlinedlist.com/user/ad%C3%A1%20x/status/a%20b%23c"
        )
    }

    func test_givenSlashInIDOrHandle_whenBuildingPermalink_thenSlashIsEncodedNotForged() {
        // Given hostile / malformed values containing a path separator.
        // When we build the permalink.
        let url = MessagePermalink.url(forMessageID: "abc/../admin", authorUsername: "ada/../root")

        // Then the slashes are encoded — neither value can forge extra path
        // segments, so the link always points inside /user/…/status/.
        XCTAssertEqual(
            url?.absoluteString,
            "https://interlinedlist.com/user/ada%2F..%2Froot/status/abc%2F..%2Fadmin"
        )
    }

    func test_givenSurroundingWhitespace_whenBuildingPermalink_thenTrimmed() {
        // Given an id and handle padded by whitespace.
        // When / Then — trimmed, not encoded as %20 padding.
        XCTAssertEqual(
            MessagePermalink.url(forMessageID: "  abc  ", authorUsername: "  ada  ")?.absoluteString,
            "https://interlinedlist.com/user/ada/status/abc"
        )
    }

    func test_givenHTMLSensitiveValues_whenBuildingEmbedHTML_thenEveryAttributeIsEscaped() {
        // Given an id that would otherwise break out of its attribute.
        let html = MessagePermalink.embedHTML(
            forMessageID: #"a"><script>x</script>&"#,
            authorUsername: "ada"
        )

        // Then the raw id is HTML-escaped inside data-message-id — no quote
        // closes the attribute and no tag is injected — and "&" is escaped
        // first so the other entities are not double-mangled.
        XCTAssertEqual(
            html?.contains(#"data-message-id="a&quot;&gt;&lt;script&gt;x&lt;/script&gt;&amp;""#),
            true
        )
        XCTAssertEqual(html?.contains("<script>x</script>"), false)
    }

    func test_givenBaseWithQuerySensitiveCharacters_whenBuildingEmbedHTML_thenHrefIsEscaped() {
        // Given a base whose ampersand would split the href attribute.
        let base = URL(string: "https://example.test/app?a=1&b=2")!

        // When we build the embed code.
        let html = MessagePermalink.embedHTML(forMessageID: "id1", authorUsername: "ada", base: base)

        // Then the ampersand is entity-escaped in both the href and the script src.
        XCTAssertEqual(html?.contains("&amp;b=2"), true)
        XCTAssertEqual(html?.contains("?a=1&b=2"), false)
    }

    // MARK: - Helpers

    private static func makeMessage(
        id: String,
        username: String,
        visibility: Visibility = .public
    ) -> Message {
        Message(
            id: id,
            author: UserSummary(id: "u1", username: username, displayName: "Ada"),
            text: "hello",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            visibility: visibility,
            digCount: 0,
            didDig: false,
            repostCount: 0
        )
    }
}
