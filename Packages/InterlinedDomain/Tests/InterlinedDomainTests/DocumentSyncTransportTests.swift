import XCTest
import InterlinedKit
@testable import InterlinedDomain

// MARK: - KitDocumentSyncTransport quartet

/// BDD-named coverage for `KitDocumentSyncTransport` focused on the nil-safe
/// rate-limit-info path: absent headers must not throw, warn, or stall sync.
final class DocumentSyncTransportTests: XCTestCase {

    // MARK: pullDelta — Happy path

    func test_givenSyncResponseWithRateLimitHeaders_whenPullDelta_thenDeltaCarriesRateLimitInfo() async throws {
        // Given — spy returns rate-limit info alongside the sync DTO.
        let expected = RateLimitInfo(limit: 100, remaining: 97)
        let spy = SpyAPIClient(rateLimitInfo: expected)
        let transport = KitDocumentSyncTransport(api: spy)

        // When
        let delta = try await transport.pullDelta(since: nil)

        // Then — rate-limit info is threaded through into the delta.
        XCTAssertEqual(delta.rateLimitInfo, expected)
    }

    // MARK: pullDelta — Absent headers (the "no limit on this route" case)

    func test_givenSyncResponseWithNoRateLimitHeaders_whenPullDelta_thenDeltaHasNilRateLimitInfo() async throws {
        // Given — spy returns nil (simulates a route that emits no headers).
        let spy = SpyAPIClient(rateLimitInfo: nil)
        let transport = KitDocumentSyncTransport(api: spy)

        // When
        let delta = try await transport.pullDelta(since: nil)

        // Then — nil is the correct "no limit" signal; no error, no warning.
        XCTAssertNil(delta.rateLimitInfo, "Absent rate-limit headers must yield nil, not an error")
        // Documents and folders are still mapped correctly.
        XCTAssertTrue(delta.documents.isEmpty)
        XCTAssertTrue(delta.folders.isEmpty)
    }

    // MARK: pullDelta — Upstream API failure

    func test_givenAPIFailure_whenPullDelta_thenThrows() async throws {
        // Given — spy throws before returning any response.
        let spy = SpyAPIClient(error: .rateLimited(serverMessage: "too fast", retryAfter: 5))
        let transport = KitDocumentSyncTransport(api: spy)

        // When / Then — error surfaces cleanly; no delta is returned.
        do {
            _ = try await transport.pullDelta(since: nil)
            XCTFail("Expected an APIError to be thrown")
        } catch let error as APIError {
            guard case .rateLimited = error else {
                return XCTFail("Expected .rateLimited, got \(error)")
            }
        }
    }

    // MARK: pushChange — Rate-limit nil guard (boundary: nil → proceed at full pace)

    func test_givenPushChangeWithNoRateLimitHeaders_whenPushChange_thenCompletesWithoutError() async throws {
        // Given — spy returns nil rate-limit info (most routes omit these headers).
        let spy = SpyAPIClient(rateLimitInfo: nil)
        let transport = KitDocumentSyncTransport(api: spy)
        let change = DocumentChange.createDocument(
            id: "doc-1",
            folderId: nil,
            title: "Untitled",
            body: "",
            isPublic: false
        )

        // When / Then — nil guard must not stall or throw; full-pace path completes.
        try await transport.pushChange(change)
    }
}

// MARK: - Local spy

/// Minimal `APIClientProtocol` spy that returns configurable rate-limit info
/// from `sendWithRateLimitInfo`. Decodes from a fixed empty sync-response
/// JSON so both `DocumentSyncResponse` and `DocumentSyncResultDTO` resolve.
private actor SpyAPIClient: APIClientProtocol {

    /// An empty sync response that satisfies both `DocumentSyncResponse`
    /// and `DocumentSyncResultDTO` (same wire shape).
    private static let emptyDeltaJSON = #"{"syncedAt":null,"folders":[],"documents":[]}"#

    private let rateLimitInfo: RateLimitInfo?
    private let error: APIError?

    init(rateLimitInfo: RateLimitInfo? = nil, error: APIError? = nil) {
        self.rateLimitInfo = rateLimitInfo
        self.error = error
    }

    func send<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> Response {
        if let e = error { throw e }
        return try JSONCoders.makeDecoder().decode(
            Response.self,
            from: Data(Self.emptyDeltaJSON.utf8)
        )
    }

    func sendVoid<Response>(_ request: Request<Response>) async throws {
        if let e = error { throw e }
    }

    func sendRaw<Response>(
        _ request: Request<Response>
    ) async throws -> (Data, String?) {
        throw APIError.transport(message: "sendRaw not wired in SpyAPIClient")
    }

    func sendWithRateLimitInfo<Response: Decodable & Sendable>(
        _ request: Request<Response>
    ) async throws -> (Response, RateLimitInfo?) {
        if let e = error { throw e }
        let decoded = try JSONCoders.makeDecoder().decode(
            Response.self,
            from: Data(Self.emptyDeltaJSON.utf8)
        )
        return (decoded, rateLimitInfo)
    }
}
