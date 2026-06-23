import Foundation
import InterlinedKit

// MARK: - ListsError

/// Domain-level errors surfaced by `ListsService`. Transport / status /
/// decode failures continue to surface as `APIError` — these are the
/// domain-layer error cases the kit cannot express.
public enum ListsError: Error, Sendable, Equatable {

    /// The current account is not entitled to manage lists. Raised when
    /// `EntitlementsService.canManageLists == false`, before any HTTP call
    /// is made. M3 ships this gate defensively per the M3 brief; M6 wires
    /// the real subscriber check.
    case subscriberRequired

    /// The schema DSL returned by the API failed to parse. The raw string
    /// is included so the editor can fall back to raw-text mode rather than
    /// silently surfacing an empty schema.
    case malformedSchema(raw: String, reason: SchemaDSLError)
}

extension ListsError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .subscriberRequired:
            return "Managing lists requires an active subscription."
        case .malformedSchema(let raw, let reason):
            return "Schema \"\(raw)\" could not be parsed: \(reason.description)"
        }
    }
}

// MARK: - ListsServicing

/// The lists surface the App layer codes against — read (public browse) +
/// write (owned-list CRUD, schema, rows, watchers, connections).
///
/// **M1 surface (read-only, public browse).** `publicLists` / `publicList` /
/// `publicRows` against `/api/users/[username]/lists*`. No auth, no
/// subscriber gating.
///
/// **M3 surface (authenticated owned-list management).** `myLists` / `detail`
/// / `create` / `update` / `delete`, the schema reads/writes, row CRUD,
/// watcher management, and the connections graph. Every M3 write method
/// consults `EntitlementsService.canManageLists` before making the HTTP
/// call; on `false` it throws `ListsError.subscriberRequired`.
///
/// Follows the same DI shape as `MessagesServicing`: takes its
/// `APIClientProtocol` and `EntitlementsService` as parameters so unit
/// tests run against a stub and exercise the gate independently of the
/// network.
public protocol ListsServicing: Sendable {

    // MARK: - M1 public browse

    /// Loads one page of `username`'s public lists.
    func publicLists(username: String, limit: Int, offset: Int) async throws -> ListsPage

    /// Loads a single public list by slug or id.
    func publicList(username: String, slug: String) async throws -> ListDetail

    /// Loads one page of rows from a public list.
    func publicRows(
        username: String,
        slug: String,
        limit: Int,
        offset: Int
    ) async throws -> RowsPage

    // MARK: - M3 owned list CRUD

    /// Loads one page of the signed-in user's lists.
    func myLists(limit: Int, offset: Int) async throws -> OwnedListsPage

    /// Loads a single owned list by id.
    func detail(listId: String) async throws -> OwnedList

    /// Creates a new list.
    func create(
        title: String,
        description: String?,
        schema: String?,
        parentId: String?,
        isPublic: Bool
    ) async throws -> OwnedList

    /// Updates a list's metadata. All parameters are optional partial fields.
    func update(
        listId: String,
        title: String?,
        description: String?,
        isPublic: Bool?,
        parentId: String?
    ) async throws -> OwnedList

    /// Deletes a list. Does not throw on missing-list — surfaces the API's
    /// `404` as an `APIError.notFound` so the caller can decide.
    func delete(listId: String) async throws

    // MARK: - M3 schema

    /// Reads the typed schema of a list. Parses the DSL string returned by
    /// `GET /api/lists/[id]/schema`. Throws `ListsError.malformedSchema`
    /// when the server returns a malformed DSL.
    func schema(of listId: String) async throws -> ListSchema

    /// Writes a typed schema to a list. Serializes the schema to the DSL
    /// form before posting.
    func updateSchema(of listId: String, schema: ListSchema) async throws -> ListSchema

    // MARK: - M3 refresh (GitHub-backed)

    /// Refreshes a GitHub-backed list against its source. Returns the
    /// freshly-refreshed list.
    func refresh(listId: String) async throws -> OwnedList

    // MARK: - M3 row CRUD

    /// Loads one page of rows of an owned list.
    func rows(of listId: String, limit: Int, offset: Int) async throws -> RowsPage

    /// Loads one row by id from an owned list.
    func row(listId: String, rowId: String) async throws -> ListRow

    /// Creates a row in an owned list. `data` is the schema-typed cell map;
    /// the service projects it back into the wire shape.
    func createRow(listId: String, data: [String: ListCellValue]) async throws -> ListRow

    /// Patches an existing row.
    func updateRow(
        listId: String,
        rowId: String,
        data: [String: ListCellValue]
    ) async throws -> ListRow

    /// Deletes a row.
    func deleteRow(listId: String, rowId: String) async throws

    // MARK: - M3 watchers

    /// Loads every watcher on a list.
    func watchers(of listId: String) async throws -> [ListWatcher]

    /// Loads the caller's own watcher status on a list.
    func myWatcherStatus(of listId: String) async throws -> WatcherStatus

    /// Loads the watcher list with `username` populated.
    func watcherUsers(of listId: String) async throws -> [ListWatcher]

    /// Grants or updates a watcher's role on a list.
    func setWatcher(
        listId: String,
        userId: String,
        role: WatcherRole
    ) async throws -> ListWatcher

    /// Revokes a watcher from a list.
    func removeWatcher(listId: String, userId: String) async throws

    // MARK: - M3 connections

    /// Loads every connection between any two lists the caller can see.
    /// The kit endpoint is global (`/api/lists/connections`) — the
    /// `listId` parameter is the focused-list id the caller will filter
    /// on locally. Passing `nil` returns every connection.
    func connections(of listId: String?) async throws -> [ListConnection]

    /// Creates a directed connection between two lists.
    func addConnection(
        fromListId: String,
        toListId: String,
        label: String?
    ) async throws -> ListConnection

    /// Removes a connection by id.
    func removeConnection(connectionId: String) async throws
}

// MARK: - ListsService

public final class ListsService: ListsServicing {

    private let api: APIClientProtocol
    private let entitlements: EntitlementsService
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    ///   - entitlements: subscriber gate. M3 ships this defensively; M6
    ///     wires the real source. Defaults to a permissive (`free`-status)
    ///     instance because `canManageLists` is currently permissive by
    ///     decision (see `EntitlementsService.canManageLists`).
    ///   - decoder: shared kit JSON configuration. Defaults to the kit's
    ///     `JSONCoders` decoder so dates parse identically to the client.
    public init(
        api: APIClientProtocol,
        entitlements: EntitlementsService = EntitlementsService(customerStatus: .free),
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) {
        self.api = api
        self.entitlements = entitlements
        self.decoder = decoder
    }

    // MARK: - M1 public browse

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

    // MARK: - M3 owned list CRUD

    public func myLists(limit: Int, offset: Int) async throws -> OwnedListsPage {
        try requireListManagement()
        let request = Lists.list(limit: limit, offset: offset)
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "data"
        let paginated = try PaginatedDecoder.decode(
            ListDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        return OwnedListsPage(from: paginated)
    }

    public func detail(listId: String) async throws -> OwnedList {
        try requireListManagement()
        let dto = try await api.send(Lists.get(id: listId))
        return OwnedList(from: dto)
    }

    public func create(
        title: String,
        description: String?,
        schema: String?,
        parentId: String?,
        isPublic: Bool
    ) async throws -> OwnedList {
        try requireListManagement()
        let request = CreateListRequest(
            title: title,
            description: description,
            schema: schema,
            parentId: parentId,
            isPublic: isPublic
        )
        let dto = try await api.send(Lists.create(request))
        return OwnedList(from: dto)
    }

    public func update(
        listId: String,
        title: String?,
        description: String?,
        isPublic: Bool?,
        parentId: String?
    ) async throws -> OwnedList {
        try requireListManagement()
        let request = UpdateListRequest(
            title: title,
            description: description,
            isPublic: isPublic,
            parentId: parentId
        )
        let dto = try await api.send(Lists.update(id: listId, request))
        return OwnedList(from: dto)
    }

    public func delete(listId: String) async throws {
        try requireListManagement()
        try await api.sendVoid(Lists.delete(id: listId))
    }

    // MARK: - M3 schema

    public func schema(of listId: String) async throws -> ListSchema {
        try requireListManagement()
        let dto = try await api.send(Lists.schema(id: listId))
        return try parseSchema(dto.schema)
    }

    public func updateSchema(of listId: String, schema: ListSchema) async throws -> ListSchema {
        try requireListManagement()
        let dsl = SchemaDSL.serialize(schema)
        let request = UpdateListSchemaRequest(schema: dsl)
        let dto = try await api.send(Lists.updateSchema(id: listId, request))
        return try parseSchema(dto.schema)
    }

    // MARK: - M3 refresh

    public func refresh(listId: String) async throws -> OwnedList {
        try requireListManagement()
        let dto = try await api.send(Lists.refresh(id: listId))
        return OwnedList(from: dto)
    }

    // MARK: - M3 row CRUD

    public func rows(of listId: String, limit: Int, offset: Int) async throws -> RowsPage {
        try requireListManagement()
        let request = Lists.rows(listId: listId, limit: limit, offset: offset)
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

    public func row(listId: String, rowId: String) async throws -> ListRow {
        try requireListManagement()
        let dto = try await api.send(Lists.row(listId: listId, rowId: rowId))
        return ListRow(from: dto)
    }

    public func createRow(listId: String, data: [String: ListCellValue]) async throws -> ListRow {
        try requireListManagement()
        let wire = data.mapValues(ListJSONValue.init(from:))
        let request = CreateListRowRequest(rowData: wire)
        let dto = try await api.send(Lists.createRow(listId: listId, request))
        return ListRow(from: dto)
    }

    public func updateRow(
        listId: String,
        rowId: String,
        data: [String: ListCellValue]
    ) async throws -> ListRow {
        try requireListManagement()
        let wire = data.mapValues(ListJSONValue.init(from:))
        let request = UpdateListRowRequest(rowData: wire)
        let dto = try await api.send(Lists.updateRow(listId: listId, rowId: rowId, request))
        return ListRow(from: dto)
    }

    public func deleteRow(listId: String, rowId: String) async throws {
        try requireListManagement()
        try await api.sendVoid(Lists.deleteRow(listId: listId, rowId: rowId))
    }

    // MARK: - M3 watchers

    public func watchers(of listId: String) async throws -> [ListWatcher] {
        try requireListManagement()
        let dtos = try await api.send(Lists.watchers(listId: listId))
        return dtos.map(ListWatcher.init(from:))
    }

    public func myWatcherStatus(of listId: String) async throws -> WatcherStatus {
        try requireListManagement()
        let dto = try await api.send(Lists.myWatcherStatus(listId: listId))
        return WatcherStatus(from: dto)
    }

    public func watcherUsers(of listId: String) async throws -> [ListWatcher] {
        try requireListManagement()
        let dtos = try await api.send(Lists.watcherUsers(listId: listId))
        return dtos.map(ListWatcher.init(from:))
    }

    public func setWatcher(
        listId: String,
        userId: String,
        role: WatcherRole
    ) async throws -> ListWatcher {
        try requireListManagement()
        let request = UpdateListWatcherRequest(role: role.wireToken)
        let dto = try await api.send(Lists.setWatcher(listId: listId, userId: userId, request))
        return ListWatcher(from: dto)
    }

    public func removeWatcher(listId: String, userId: String) async throws {
        try requireListManagement()
        try await api.sendVoid(Lists.removeWatcher(listId: listId, userId: userId))
    }

    // MARK: - M3 connections

    public func connections(of listId: String?) async throws -> [ListConnection] {
        try requireListManagement()
        let response = try await api.send(Lists.connections())
        let all = response.connections.map(ListConnection.init(from:))
        guard let listId else { return all }
        return all.filter { $0.fromListId == listId || $0.toListId == listId }
    }

    public func addConnection(
        fromListId: String,
        toListId: String,
        label: String?
    ) async throws -> ListConnection {
        try requireListManagement()
        let request = CreateListConnectionRequest(
            fromListId: fromListId,
            toListId: toListId,
            label: label
        )
        let dto = try await api.send(Lists.createConnection(request))
        return ListConnection(from: dto)
    }

    public func removeConnection(connectionId: String) async throws {
        try requireListManagement()
        try await api.sendVoid(Lists.deleteConnection(id: connectionId))
    }

    // MARK: - Internals

    /// The single entitlement gate every M3 write method routes through.
    /// Throws `ListsError.subscriberRequired` when the account is not
    /// entitled to manage lists. M3 ships this defensively; the actual
    /// `canManageLists` body becomes restrictive in M6.
    private func requireListManagement() throws {
        guard entitlements.canManageLists else {
            throw ListsError.subscriberRequired
        }
    }

    /// Parses a DSL string into a `ListSchema`, projecting `SchemaDSLError`
    /// into the richer `ListsError.malformedSchema` so the editor can
    /// surface both the raw string and the precise reason.
    private func parseSchema(_ raw: String) throws -> ListSchema {
        do {
            return try SchemaDSL.parse(raw)
        } catch let error as SchemaDSLError {
            throw ListsError.malformedSchema(raw: raw, reason: error)
        }
    }
}

// MARK: - Wire projection helper

/// Recursive projection from the domain's loose `ListCellValue` back to the
/// kit's `ListJSONValue` — used when writing rows. The two enums are
/// structurally identical (M1 chose to project the wire union into a domain
/// equivalent so view code never sees `ListJSONValue`); this is the inverse
/// of the `init(from value:)` already in `ListMappers.swift`.
extension ListJSONValue {
    fileprivate init(from value: ListCellValue) {
        switch value {
        case .null: self = .null
        case .bool(let v): self = .bool(v)
        case .int(let v): self = .int(v)
        case .double(let v): self = .double(v)
        case .string(let v): self = .string(v)
        case .array(let items):
            self = .array(items.map(ListJSONValue.init(from:)))
        case .object(let dict):
            self = .object(dict.mapValues(ListJSONValue.init(from:)))
        }
    }
}
