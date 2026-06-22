import Foundation
import InterlinedKit

// MARK: - ListsServicing

/// The public-list browse surface the App layer codes against for the M1
/// read-only core (PLAN.md §1 "Public list browsing", §6 M1).
///
/// M1 covers the three no-auth browse endpoints under
/// `/api/users/[username]/lists*` only — no list CRUD, no schema editing, no
/// watchers, no GitHub refresh. Those land in M3 as a separate, authenticated
/// surface on this same service (or a sibling `MyListsServicing`).
///
/// Follows the same DI shape as `MessagesServicing`: takes its
/// `APIClientProtocol` as a parameter so unit tests run against a stub.
public protocol ListsServicing: Sendable {

    /// Loads one page of `username`'s public lists. Mirrors
    /// `MessagesServicing.timeline` — the App layer's infinite-scroll machinery
    /// is uniform across the read surfaces.
    func publicLists(username: String, limit: Int, offset: Int) async throws -> ListsPage

    /// Loads a single public list by its slug (or id — the path accepts either).
    func publicList(username: String, slug: String) async throws -> ListDetail

    /// Loads one page of rows from a public list. The row shape is loose for
    /// M1 (`[String: ListCellValue]`); the typed schema-aware editor lands in
    /// M3.
    func publicRows(
        username: String,
        slug: String,
        limit: Int,
        offset: Int
    ) async throws -> RowsPage
}

// MARK: - ListsService

public final class ListsService: ListsServicing {

    private let api: APIClientProtocol
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    ///   - decoder: shared kit JSON configuration. Defaults to the kit's
    ///     `JSONCoders` decoder so dates parse identically to the client.
    public init(
        api: APIClientProtocol,
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) {
        self.api = api
        self.decoder = decoder
    }

    // MARK: Public browse

    public func publicLists(
        username: String,
        limit: Int,
        offset: Int
    ) async throws -> ListsPage {
        let request = Lists.publicLists(
            username: username,
            limit: limit,
            offset: offset
        )
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "data"
        let paginated = try PaginatedDecoder.decode(
            ListDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        return ListsPage(from: paginated)
    }

    public func publicList(
        username: String,
        slug: String
    ) async throws -> ListDetail {
        // The kit's `publicList(username:id:)` accepts an id or a slug — the
        // path component is opaque to the request builder. The domain
        // parameter is named `slug` to match the M1 UI vocabulary while still
        // accepting either form.
        let dto = try await api.send(Lists.publicList(username: username, id: slug))
        return ListDetail(from: dto)
    }

    public func publicRows(
        username: String,
        slug: String,
        limit: Int,
        offset: Int
    ) async throws -> RowsPage {
        let request = Lists.publicListRows(
            username: username,
            id: slug,
            limit: limit,
            offset: offset
        )
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "data"
        let paginated = try PaginatedDecoder.decode(
            ListRowDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        return RowsPage(from: paginated)
    }
}
