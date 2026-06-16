import Foundation
import XCTest
@testable import InterlinedKit

/// Test helper mirroring how the service layer consumes a paginated request.
///
/// `Paginated<T>` is intentionally **not** `Decodable` (its collection key is
/// runtime-known, supplied via `Request.paginationKey`), so endpoint builders
/// that return `Request<Paginated<T>>` are decoded with `PaginatedDecoder`
/// rather than `APIClient.send`. This helper performs the raw round-trip and
/// decodes with the request's own `paginationKey` — exactly the path the
/// real services will take — so the endpoint tests exercise both the builder
/// metadata and the envelope decode in one shot.
extension XCTestCase {
    func fetchPaginated<Item: Decodable & Sendable>(
        _ itemType: Item.Type,
        request: Request<Paginated<Item>>,
        using client: APIClient
    ) async throws -> Paginated<Item> {
        let key = try XCTUnwrap(request.paginationKey, "Paginated request must carry a paginationKey")
        let (data, _) = try await client.sendRaw(request)
        return try PaginatedDecoder.decode(itemType, collectionKey: key, from: data)
    }
}
