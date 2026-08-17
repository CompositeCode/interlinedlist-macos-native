// ShareURLParserTests
//
// BDD-named tests for the pure share-URL parser (work-consolidation.md G3). The
// parser feeds both the `interlinedlist://` deep-link handler and the
// pasted-URL path, so its recognition surface is exhaustively covered
// here:
//   - happy: https + custom-scheme list/document URLs parse to the right
//     kind + token.
//   - invalid input: a non-share URL (timeline, profile, garbage) returns
//     nil; the OAuth-callback URL returns nil so the existing handler is
//     untouched.
//   - upstream failure: N/A (pure parser — no service).
//   - empty / boundary: a trailing-slash / empty-token URL returns nil;
//     whitespace around a pasted string is trimmed.
//   - `handle(_:)` posts only for recognized URLs and returns false for
//     the OAuth callback (routing test).

import XCTest
@testable import InterlinedList

@MainActor
final class ShareURLParserTests: XCTestCase {

    // MARK: - Happy path (https)

    func test_givenHttpsListShareURL_whenParsing_thenReturnsListKindAndToken() {
        let url = URL(string: "https://interlinedlist.com/lists/shared/abc123")!
        XCTAssertEqual(ShareURLParser.parse(url), ParsedShare(kind: .list, token: "abc123"))
    }

    func test_givenHttpsDocumentShareURL_whenParsing_thenReturnsDocumentKindAndToken() {
        let url = URL(string: "https://interlinedlist.com/documents/shared/DoC-9")!
        XCTAssertEqual(ShareURLParser.parse(url), ParsedShare(kind: .document, token: "DoC-9"))
    }

    func test_givenWwwHostShareURL_whenParsing_thenHostIgnoredAndParses() {
        let url = URL(string: "https://www.interlinedlist.com/lists/shared/tok")!
        XCTAssertEqual(ShareURLParser.parse(url), ParsedShare(kind: .list, token: "tok"))
    }

    // MARK: - Happy path (custom scheme)

    func test_givenCustomSchemeListURL_whenParsing_thenParsesHostAsResource() {
        // interlinedlist://lists/shared/tok → host == "lists".
        let url = URL(string: "interlinedlist://lists/shared/tok")!
        XCTAssertEqual(ShareURLParser.parse(url), ParsedShare(kind: .list, token: "tok"))
    }

    func test_givenCustomSchemeShareRouterURL_whenParsing_thenSkipsShareSegment() {
        // interlinedlist://share/documents/shared/tok → host == "share".
        let url = URL(string: "interlinedlist://share/documents/shared/tok")!
        XCTAssertEqual(ShareURLParser.parse(url), ParsedShare(kind: .document, token: "tok"))
    }

    // MARK: - Invalid input

    func test_givenNonShareURL_whenParsing_thenReturnsNil() {
        XCTAssertNil(ShareURLParser.parse(URL(string: "https://interlinedlist.com/timeline")!))
        XCTAssertNil(ShareURLParser.parse(URL(string: "https://interlinedlist.com/lists/L1")!))
    }

    func test_givenExtraTrailingSegments_whenParsing_thenReturnsNil() {
        // The token must be the last segment; extra segments after it mean
        // this is not the canonical share URL, so it must not resolve.
        let url = URL(string: "https://interlinedlist.com/lists/shared/tok/extra/more")!
        XCTAssertNil(ShareURLParser.parse(url))
    }

    func test_givenOAuthCallbackURL_whenParsing_thenReturnsNil() {
        // The OAuth callback must not be mistaken for a share link.
        let url = URL(string: "interlinedlist://oauth/callback?code=xyz&state=abc")!
        XCTAssertNil(ShareURLParser.parse(url))
    }

    func test_givenWrongResourceWord_whenParsing_thenReturnsNil() {
        let url = URL(string: "https://interlinedlist.com/folders/shared/tok")!
        XCTAssertNil(ShareURLParser.parse(url))
    }

    // MARK: - Empty / boundary

    func test_givenEmptyToken_whenParsing_thenReturnsNil() {
        // Trailing slash → the token segment is empty/absent.
        let url = URL(string: "https://interlinedlist.com/lists/shared/")!
        XCTAssertNil(ShareURLParser.parse(url))
    }

    func test_givenWhitespaceWrappedString_whenParsing_thenTrimmedAndParses() {
        let parsed = ShareURLParser.parse(string: "  https://interlinedlist.com/lists/shared/tok\n")
        XCTAssertEqual(parsed, ParsedShare(kind: .list, token: "tok"))
    }

    func test_givenGarbageString_whenParsing_thenReturnsNil() {
        XCTAssertNil(ShareURLParser.parse(string: "not a url at all !!"))
        XCTAssertNil(ShareURLParser.parse(string: "   "))
    }

    // MARK: - webURL builder

    func test_givenTokenAndBase_whenBuildingWebURL_thenComposesCanonicalPath() {
        let base = URL(string: "https://interlinedlist.com")!
        let listURL = ShareURLParser.webURL(base: base, kind: .list, token: "tok")
        XCTAssertEqual(listURL?.absoluteString, "https://interlinedlist.com/lists/shared/tok")
        let docURL = ShareURLParser.webURL(base: base, kind: .document, token: "tok")
        XCTAssertEqual(docURL?.absoluteString, "https://interlinedlist.com/documents/shared/tok")
    }

    // MARK: - handle() routing (posts only for share links)

    func test_givenShareURL_whenHandling_thenPostsParsedAndReturnsTrue() {
        var captured: ParsedShare?
        let handled = ShareLinkDeepLink.handle(
            URL(string: "https://interlinedlist.com/documents/shared/tok")!,
            post: { captured = $0 }
        )
        XCTAssertTrue(handled)
        XCTAssertEqual(captured, ParsedShare(kind: .document, token: "tok"))
    }

    func test_givenOAuthURL_whenHandling_thenDoesNotPostAndReturnsFalse() {
        var captured: ParsedShare?
        let handled = ShareLinkDeepLink.handle(
            URL(string: "interlinedlist://oauth/callback?code=1")!,
            post: { captured = $0 }
        )
        XCTAssertFalse(handled, "The OAuth callback must fall through to its own handler")
        XCTAssertNil(captured)
    }
}
