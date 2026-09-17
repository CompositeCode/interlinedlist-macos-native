import XCTest
@testable import InterlinedKit

/// G21 — link metadata / rich previews.
///
/// The payloads below are **verbatim live responses** captured 2026-09-07 from
/// `https://interlinedlist.com` under a Bearer token from the `.env` test
/// account, not hand-written guesses. They pin the nested `metadata` shape that
/// the pre-G21 flat `LinkPreviewDTO` silently decoded to all-nil.
final class LinkMetadataTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        // The API's configured decoder (ISO8601 dates), not a bare JSONDecoder —
        // MessageDTO's date fields only decode under this configuration.
        try JSONCoders.makeDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Happy path

    /// GIVEN the live `GET /api/link-metadata` body
    /// WHEN decoded
    /// THEN the nested metadata fields land on the flat DTO properties.
    func test_givenLiveNestedLinkBody_whenDecoded_thenMetadataFieldsArePopulated() throws {
        let json = """
        {"link":{"url":"https://github.com","platform":"other","metadata":{"type":"link",\
        "title":"GitHub · Change is constant.","description":"Join the world's most widely adopted platform.",\
        "thumbnail":"https://images.ctfassets.net/hero.png","ogType":"object"},\
        "fetchStatus":"success","fetchedAt":"2026-09-07T06:25:45.065Z"}}
        """
        let response = try decode(LinkMetadataResponse.self, json)
        let link = response.link

        XCTAssertEqual(link.url, "https://github.com")
        XCTAssertEqual(link.platform, "other")
        XCTAssertEqual(link.fetchStatus, "success")
        XCTAssertEqual(link.fetchedAt, "2026-09-07T06:25:45.065Z")
        // The regression this whole gap turns on: these were nil before G21.
        XCTAssertEqual(link.title, "GitHub · Change is constant.")
        XCTAssertEqual(link.description, "Join the world's most widely adopted platform.")
        XCTAssertEqual(link.imageUrl, "https://images.ctfassets.net/hero.png")
    }

    /// GIVEN a message's embedded `linkMetadata` in the live nested shape
    /// WHEN the message is decoded
    /// THEN the preview carries its title and thumbnail.
    func test_givenLiveEmbeddedLinkMetadata_whenMessageDecoded_thenPreviewIsPopulated() throws {
        let json = """
        {"id":"d05faf17","content":"post","publiclyVisible":true,"userId":"u1",\
        "createdAt":"2026-09-06T21:34:00.000Z","updatedAt":"2026-09-06T21:34:00.000Z",\
        "digCount":0,"pushCount":0,"dugByMe":false,\
        "user":{"id":"u1","username":"tester"},\
        "linkMetadata":{"links":[{"url":"https://compositecode.blog/2026/08/19/worktrees/",\
        "metadata":{"type":"link","title":"Maximize Git Efficiency","ogType":"article",\
        "thumbnail":"https://i0.wp.com/hero.png","description":"Git's one-tree problem."},\
        "platform":"other","fetchedAt":"2026-09-06T21:34:31.989Z","fetchStatus":"success"}]}}
        """
        let dto = try decode(MessageDTO.self, json)
        let preview = try XCTUnwrap(dto.linkMetadata?.links.first)

        XCTAssertEqual(preview.title, "Maximize Git Efficiency")
        XCTAssertEqual(preview.imageUrl, "https://i0.wp.com/hero.png")
        XCTAssertEqual(preview.description, "Git's one-tree problem.")
    }

    // MARK: - Invalid input

    /// GIVEN a link entry with no `url`
    /// WHEN decoded
    /// THEN it throws — `url` is the one field the DTO cannot synthesise.
    func test_givenLinkWithoutURL_whenDecoded_thenThrows() {
        let json = #"{"link":{"platform":"other","fetchStatus":"success"}}"#
        XCTAssertThrowsError(try decode(LinkMetadataResponse.self, json))
    }

    // MARK: - Upstream failure

    /// GIVEN the live body for a URL the server could not fetch
    /// WHEN decoded
    /// THEN it decodes cleanly with `failed` status and no metadata — a failed
    /// fetch is a successful *request* and must not throw.
    func test_givenFailedFetchBody_whenDecoded_thenDecodesWithNoMetadata() throws {
        let json = """
        {"link":{"url":"https://this-host-does-not-exist-xyzzy-42.example/nope",\
        "platform":"other","fetchStatus":"failed"}}
        """
        let link = try decode(LinkMetadataResponse.self, json).link

        XCTAssertEqual(link.fetchStatus, "failed")
        XCTAssertNil(link.title)
        XCTAssertNil(link.imageUrl)
        XCTAssertNil(link.fetchedAt)
    }

    // MARK: - Boundary

    /// GIVEN the older **flat** shape (fixtures, stubs, an older server build)
    /// WHEN decoded
    /// THEN the flat keys still populate — the decoder tolerates both shapes.
    func test_givenLegacyFlatShape_whenDecoded_thenFlatKeysStillPopulate() throws {
        let json = """
        {"url":"https://example.com","platform":"other","fetchStatus":"success",\
        "title":"Flat title","description":"Flat description","imageUrl":"https://example.com/i.png"}
        """
        let link = try decode(LinkPreviewDTO.self, json)

        XCTAssertEqual(link.title, "Flat title")
        XCTAssertEqual(link.description, "Flat description")
        XCTAssertEqual(link.imageUrl, "https://example.com/i.png")
    }

    /// GIVEN a nested `metadata` present but empty
    /// WHEN decoded
    /// THEN the fields are nil rather than throwing, and `url` survives.
    func test_givenEmptyNestedMetadata_whenDecoded_thenFieldsAreNil() throws {
        let json = #"{"url":"https://example.com","metadata":{},"fetchStatus":"success"}"#
        let link = try decode(LinkPreviewDTO.self, json)

        XCTAssertEqual(link.url, "https://example.com")
        XCTAssertNil(link.title)
        XCTAssertNil(link.imageUrl)
    }

    /// GIVEN the live `GET /api/messages/[id]/metadata` body
    /// WHEN decoded
    /// THEN the bare `{links:[…]}` object decodes as `LinkMetadataDTO` — this
    /// route has no envelope key, unlike `/api/link-metadata`.
    func test_givenMessageMetadataBody_whenDecoded_thenBareLinksObjectDecodes() throws {
        let json = """
        {"links":[{"url":"https://compositecode.blog/2026/08/19/worktrees/",\
        "metadata":{"title":"Maximize Git Efficiency","thumbnail":"https://i0.wp.com/hero.png"},\
        "platform":"other","fetchStatus":"success"}]}
        """
        let dto = try decode(LinkMetadataDTO.self, json)

        XCTAssertEqual(dto.links.count, 1)
        XCTAssertEqual(dto.links.first?.title, "Maximize Git Efficiency")
    }

    // MARK: - Request builders

    func test_givenResolveRequest_whenBuilt_thenTargetsLinkMetadataWithURLQuery() {
        let request = LinkMetadata.resolve(url: "https://example.com")

        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/link-metadata")
        XCTAssertEqual(request.query.first?.name, "url")
        XCTAssertEqual(request.query.first?.value, "https://example.com")
    }

    /// The refresh call must be POST — the GET on the same path only reads, and
    /// the live `Allow` header is `GET, HEAD, OPTIONS, POST`.
    func test_givenMessageMetadataRequests_whenBuilt_thenVerbsMatchLiveAllowHeader() {
        XCTAssertEqual(LinkMetadata.forMessage(id: "m1").method, .get)
        XCTAssertEqual(LinkMetadata.forMessage(id: "m1").path, "/api/messages/m1/metadata")
        XCTAssertEqual(LinkMetadata.refreshForMessage(id: "m1").method, .post)
        XCTAssertEqual(LinkMetadata.refreshForMessage(id: "m1").path, "/api/messages/m1/metadata")
    }

    func test_givenImageProxyURL_whenBuilt_thenEncodesTargetAsQuery() throws {
        let base = try XCTUnwrap(URL(string: "https://interlinedlist.com"))
        let proxied = try XCTUnwrap(
            LinkMetadata.imageProxyURL(baseURL: base, imageURL: "https://scontent.cdninstagram.com/a.jpg")
        )

        XCTAssertEqual(proxied.path, "/api/images/proxy")
        let query = try XCTUnwrap(URLComponents(url: proxied, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "url" })?.value,
                       "https://scontent.cdninstagram.com/a.jpg")
    }
}
