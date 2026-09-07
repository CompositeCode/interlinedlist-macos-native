import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// G21 — `LinkMetadataService`.
///
/// JSON bodies are the shapes captured live 2026-09-07 (see
/// `InterlinedKitTests.LinkMetadataTests` for the raw captures).
final class LinkMetadataServiceTests: XCTestCase {

    private let base = URL(string: "https://interlinedlist.com")!

    private func makeService(_ api: StubAPIClient) -> LinkMetadataService {
        LinkMetadataService(api: api, baseURL: base)
    }

    // MARK: - Happy path

    /// GIVEN the server resolves a URL
    /// WHEN a preview is requested
    /// THEN the nested metadata is projected onto the domain model and the
    /// request carries the URL as a `url` query item.
    func test_givenResolvableURL_whenPreviewRequested_thenReturnsPopulatedPreview() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"link":{"url":"https://github.com","platform":"other","metadata":{"type":"link",\
        "title":"GitHub","description":"Build software.","thumbnail":"https://img.example/h.png"},\
        "fetchStatus":"success","fetchedAt":"2026-09-07T06:25:45.065Z"}}
        """)

        let preview = try await makeService(api).preview(for: "https://github.com")

        let unwrapped = try XCTUnwrap(preview)
        XCTAssertEqual(unwrapped.title, "GitHub")
        XCTAssertEqual(unwrapped.description, "Build software.")
        XCTAssertEqual(unwrapped.imageURL?.absoluteString, "https://img.example/h.png")

        let all = await api.recorded
        let recorded = try XCTUnwrap(all.first)
        XCTAssertEqual(recorded.path, "/api/link-metadata")
        XCTAssertEqual(recorded.query["url"], "https://github.com")
    }

    /// GIVEN a message with stored metadata
    /// WHEN read
    /// THEN the bare `{links:[…]}` body maps to domain previews.
    func test_givenStoredMessageMetadata_whenRead_thenMapsToPreviews() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"links":[{"url":"https://compositecode.blog/p","metadata":{"title":"Worktrees",\
        "thumbnail":"https://i0.wp.com/h.png"},"platform":"other","fetchStatus":"success"}]}
        """)

        let previews = try await makeService(api).stored(forMessage: "m1")

        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews.first?.title, "Worktrees")
        let all = await api.recorded
        let recorded = try XCTUnwrap(all.first)
        XCTAssertEqual(recorded.method, "GET")
        XCTAssertEqual(recorded.path, "/api/messages/m1/metadata")
    }

    /// The refresh path must POST — GET on the same path only reads.
    func test_givenRefreshRequested_whenCalled_thenPostsToMessageMetadata() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"links":[{"url":"https://example.com","metadata":{"title":"Now resolved"},\
        "fetchStatus":"success"}]}
        """)

        let previews = try await makeService(api).refresh(forMessage: "m1")

        XCTAssertEqual(previews.first?.title, "Now resolved")
        let all = await api.recorded
        let recorded = try XCTUnwrap(all.first)
        XCTAssertEqual(recorded.method, "POST")
        XCTAssertEqual(recorded.path, "/api/messages/m1/metadata")
    }

    // MARK: - Invalid input

    /// GIVEN a blank URL
    /// WHEN a preview is requested
    /// THEN no request is made — the server would answer 400 "Missing url".
    func test_givenBlankURL_whenPreviewRequested_thenNoRequestIsMade() async throws {
        let api = StubAPIClient()

        let preview = try await makeService(api).preview(for: "   ")

        XCTAssertNil(preview)
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - Upstream failure

    /// GIVEN the API fails
    /// WHEN a preview is requested
    /// THEN the error propagates rather than being swallowed into `nil`.
    func test_givenAPIFailure_whenPreviewRequested_thenErrorPropagates() async {
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))

        do {
            _ = try await makeService(api).preview(for: "https://example.com")
            XCTFail("Expected the transport error to propagate")
        } catch {
            XCTAssertTrue(error is APIError)
        }
    }

    // MARK: - Boundary

    /// GIVEN the server resolved nothing (`fetchStatus: "failed"`, no metadata)
    /// WHEN a preview is requested
    /// THEN the result is nil — a 200 with no content must not become an empty
    /// card. This is the exact shape that produced the host-only cards.
    func test_givenFailedFetch_whenPreviewRequested_thenReturnsNil() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"link":{"url":"https://nope.example/x","platform":"other","fetchStatus":"failed"}}
        """)

        let preview = try await makeService(api).preview(for: "https://nope.example/x")

        XCTAssertNil(preview)
    }

    /// An Instagram thumbnail routes through the proxy; anything else does not.
    func test_givenThumbnails_whenDisplayURLBuilt_thenOnlyInstagramIsProxied() {
        let service = makeService(StubAPIClient())

        let instagram = LinkPreview(
            url: URL(string: "https://instagram.com/p/x")!,
            title: "A post",
            imageURL: URL(string: "https://scontent.cdninstagram.com/v/a.jpg")!
        )
        let direct = LinkPreview(
            url: URL(string: "https://compositecode.blog/p")!,
            title: "A post",
            imageURL: URL(string: "https://i0.wp.com/h.png")!
        )

        let proxied = service.displayImageURL(for: instagram)
        XCTAssertEqual(proxied?.path, "/api/images/proxy")
        XCTAssertEqual(proxied?.host, "interlinedlist.com")

        XCTAssertEqual(service.displayImageURL(for: direct)?.absoluteString,
                       "https://i0.wp.com/h.png")
    }

    /// A preview with no image at all yields no display URL.
    func test_givenPreviewWithoutImage_whenDisplayURLBuilt_thenReturnsNil() {
        let service = makeService(StubAPIClient())
        let preview = LinkPreview(url: URL(string: "https://example.com")!, title: "No image")

        XCTAssertNil(service.displayImageURL(for: preview))
    }
}
