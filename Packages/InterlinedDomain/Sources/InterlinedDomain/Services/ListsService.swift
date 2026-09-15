import Foundation
import InterlinedKit

// MARK: - ListsError

/// Domain-level errors surfaced by `ListsService`. Transport / status /
/// decode failures continue to surface as `APIError` — these are the
/// domain-layer error cases the kit cannot express.
public enum ListsError: Error, Sendable, Equatable {

    /// Creating a list requires an active subscription. Raised when
    /// `EntitlementsService.canManageLists == false`, before any HTTP call is
    /// made.
    ///
    /// **Creation only.** Reading a list, editing one, adding or editing rows,
    /// managing watchers, and managing connections stay free — the published
    /// matrix says a lapsed subscriber keeps existing lists "fully usable" and
    /// that "adding rows to an existing list is free". Do not reintroduce this
    /// gate on those paths (GitHub #40).
    case subscriberRequired

    /// The schema DSL returned by the API failed to parse. The raw string
    /// is included so the editor can fall back to raw-text mode rather than
    /// silently surfacing an empty schema.
    case malformedSchema(raw: String, reason: SchemaDSLError)

    /// An add-watcher call named no user. Raised before any HTTP call because
    /// the route treats a missing `userId` as "subscribe *me* to this list",
    /// which is a different action entirely (work-consolidation.md G23).
    case invalidWatcher
}

extension ListsError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .subscriberRequired:
            return "Managing lists requires an active subscription."
        case .malformedSchema(let raw, let reason):
            return "Schema \"\(raw)\" could not be parsed: \(reason.description)"
        case .invalidWatcher:
            return "Choose a person to share this list with."
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
/// **Authenticated owned-list management.** `myLists` / `detail` / `create` /
/// `update` / `delete`, the schema reads/writes, row CRUD, watcher management,
/// and the connections graph.
///
/// Only `create` is subscriber-gated: it consults
/// `EntitlementsService.canManageLists` before making the HTTP call and throws
/// `ListsError.subscriberRequired` on `false`. Everything else is free, because
/// the subscription gates creation and nothing else (GitHub #40).
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
    ///
    /// When a `ListsStore` is injected the **first** page (`offset == 0`) is
    /// written through to the cache; if the live fetch fails and the cache
    /// holds a prior non-empty owned-list slice, that cached slice is returned
    /// as a single page instead of throwing (stale-while-revalidate / offline
    /// fallback — mirrors `MessagesService.timeline`).
    func myLists(limit: Int, offset: Int) async throws -> OwnedListsPage

    /// Surfaces the cached owned-list slice (when a store is injected and holds
    /// one), so the sidebar can paint before `myLists` returns. Empty when no
    /// store is injected or the cache is cold.
    func cachedMyLists() async -> [OwnedList]

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

    // MARK: - G23 shared with me

    /// Loads one page of lists **other people** shared with the caller
    /// (`GET /api/lists/watching`). Distinct from `myLists`, which returns the
    /// caller's own lists; the two collections never overlap.
    func watching(limit: Int, offset: Int) async throws -> WatchedListsPage

    /// Loads a list's ranked contributors, in the server's ranking order.
    /// Unpaged — the route returns every contributor.
    func contributors(of listId: String) async throws -> [ListContributor]

    /// Grants `userId` access to `listId` at `role`.
    ///
    /// Subscriber-gated server-side: a free owner gets `403`, which this
    /// method surfaces as `ListsError.subscriberRequired` so the UI can show
    /// the upsell rather than a raw HTTP error. Pass `notify: false` to grant
    /// access without emailing the recipient.
    func addWatcher(
        listId: String,
        userId: String,
        role: WatcherRole,
        notify: Bool
    ) async throws

    /// Subscribes the **caller** to a public list — the Watch button on
    /// someone else's profile (GitHub #44 / G32).
    ///
    /// This is the same route as `addWatcher`, taking its *self-subscribe*
    /// branch by omitting `userId`. That branch is deliberately **free**: the
    /// subscription gates granting someone else access, not following a list
    /// that is already public to you. Modelled as its own method rather than an
    /// optional parameter on `addWatcher`, because "add this person" and
    /// "subscribe me" are different intents that happen to share a URL — and an
    /// `addWatcher` call whose id went empty by accident must stay an error
    /// rather than quietly becoming this.
    func watch(listId: String) async throws

    // MARK: - M3 watchers

    /// Loads every watcher on a list. Owner-only server-side.
    func watchers(of listId: String) async throws -> [ListWatcher]

    /// Loads the caller's own watcher status on a list.
    func myWatcherStatus(of listId: String) async throws -> WatcherStatus

    /// Searches people the owner could add as watchers
    /// (`GET /api/lists/[id]/watchers/users`). The server auto-excludes the
    /// list's current watchers, so every result is addable.
    ///
    /// Note this is a **candidate** search, not the watcher list — use
    /// `watchers(of:)` for who already has access.
    func watcherCandidates(
        of listId: String,
        search: String?,
        limit: Int
    ) async throws -> [CollaboratorCandidate]

    /// Updates an existing watcher's role on a list.
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
    private let store: ListsStore?
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    ///   - entitlements: the subscriber gate consulted by `create`. The
    ///     default is deliberately permissive: an un-injected gate is a
    ///     composition-root wiring defect, and the server remains the real
    ///     authority, so failing open here beats locking a paying user out.
    ///     `AppEnvironment` injects the signed-in account's entitlements.
    ///   - store: optional lists cache port. When `nil`, the service fetches
    ///     live with no caching (the default keeps existing `ListsService(api:)`
    ///     call sites source-compatible).
    ///   - decoder: shared kit JSON configuration. Defaults to the kit's
    ///     `JSONCoders` decoder so dates parse identically to the client.
    public init(
        api: APIClientProtocol,
        entitlements: EntitlementsService = EntitlementsService(customerStatus: .subscriber),
        store: ListsStore? = nil,
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) {
        self.api = api
        self.entitlements = entitlements
        self.store = store
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
        do {
            let request = Lists.list(limit: limit, offset: offset)
            let (data, _) = try await api.sendRaw(request)
            let key = request.paginationKey ?? "data"
            let paginated = try PaginatedDecoder.decode(
                ListDTO.self,
                collectionKey: key,
                from: data,
                decoder: decoder
            )
            let page = OwnedListsPage(from: paginated)
            // Write through only the FIRST page — the cached owned-list slice
            // is a single page keyed under one domain (see `ListsStore` docs),
            // so a subsequent-page fetch must not overwrite it.
            if offset == 0 {
                await store?.cacheLists(page.lists)
            }
            return page
        } catch let error as APIError {
            // Offline / upstream failure: fall back to the cached first page
            // when one exists. A cold cache still surfaces the error so the UI
            // shows a real failure rather than a silent empty sidebar.
            if let store, offset == 0 {
                let cached = await store.cachedLists()
                if !cached.isEmpty {
                    return OwnedListsPage(lists: cached, hasMore: false, nextOffset: nil)
                }
            }
            throw error
        }
    }

    public func cachedMyLists() async -> [OwnedList] {
        await store?.cachedLists() ?? []
    }

    public func detail(listId: String) async throws -> OwnedList {
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
        try await api.sendVoid(Lists.delete(id: listId))
    }

    // MARK: - M3 schema

    public func schema(of listId: String) async throws -> ListSchema {
        let dto = try await api.send(Lists.schema(id: listId))
        return try parseSchema(dto.schema)
    }

    public func updateSchema(of listId: String, schema: ListSchema) async throws -> ListSchema {
        let dsl = SchemaDSL.serialize(schema)
        let request = UpdateListSchemaRequest(schema: dsl)
        let dto = try await api.send(Lists.updateSchema(id: listId, request))
        return try parseSchema(dto.schema)
    }

    // MARK: - M3 refresh

    public func refresh(listId: String) async throws -> OwnedList {
        let dto = try await api.send(Lists.refresh(id: listId))
        return OwnedList(from: dto)
    }

    // MARK: - M3 row CRUD

    public func rows(of listId: String, limit: Int, offset: Int) async throws -> RowsPage {
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
        // The live read answers `{ data }`; unwrap it.
        let dto = try await api.send(Lists.row(listId: listId, rowId: rowId)).data
        return ListRow(from: dto)
    }

    public func createRow(listId: String, data: [String: ListCellValue]) async throws -> ListRow {
        let wire = data.mapValues(ListJSONValue.init(from:))
        let request = CreateListRowRequest(rowData: wire)
        // The live create answers `{ message, data }`; unwrap it.
        let dto = try await api.send(Lists.createRow(listId: listId, request)).data
        return ListRow(from: dto)
    }

    public func updateRow(
        listId: String,
        rowId: String,
        data: [String: ListCellValue]
    ) async throws -> ListRow {
        let wire = data.mapValues(ListJSONValue.init(from:))
        let request = UpdateListRowRequest(rowData: wire)
        // The live update answers `{ message, data }`; unwrap it.
        let dto = try await api.send(Lists.updateRow(listId: listId, rowId: rowId, request)).data
        return ListRow(from: dto)
    }

    public func deleteRow(listId: String, rowId: String) async throws {
        try await api.sendVoid(Lists.deleteRow(listId: listId, rowId: rowId))
    }

    // MARK: - G23 shared with me

    /// Lists shared *with* the caller. Free on every tier — seeing what someone
    /// gave you access to is not a subscriber feature, and gating it would hide
    /// content a free user is entitled to read (#40 matrix: creation only).
    public func watching(limit: Int, offset: Int) async throws -> WatchedListsPage {
        let request = Lists.watching(limit: limit, offset: offset)
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "data"
        let paginated = try PaginatedDecoder.decode(
            ListDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        // Deliberately *not* written through `store`: the owned-list cache is a
        // single slice keyed under one domain, and folding watched lists into
        // it would make them reappear in the owned sidebar on the next
        // cache-first paint.
        return WatchedListsPage(from: paginated)
    }

    /// Free: inspecting who contributes to a list is a read.
    public func contributors(of listId: String) async throws -> [ListContributor] {
        let response = try await api.send(Lists.contributors(listId: listId))
        return response.contributors.map(ListContributor.init(from:))
    }

    public func addWatcher(
        listId: String,
        userId: String,
        role: WatcherRole,
        notify: Bool
    ) async throws {
        // Reject an empty id before spending a round-trip: an empty `userId`
        // would silently flip the route into its *self-subscribe* branch
        // (documented on /help/api/lists) and add the caller instead of the
        // intended recipient.
        let trimmedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserId.isEmpty else { throw ListsError.invalidWatcher }
        // Granting someone else access is `sharingWithPeople`, not list
        // creation — the same entitlement that gates document collaborators and
        // email invites. Checked *after* the empty-id guard so an invalid call
        // reports what is wrong with it rather than an entitlement the caller
        // may well have.
        guard entitlements.isEnabled(.sharingWithPeople) else {
            throw ListsError.subscriberRequired
        }
        let request = AddListWatcherRequest(
            userId: trimmedUserId,
            role: role.wireToken,
            notify: notify
        )
        do {
            _ = try await api.send(Lists.addWatcher(listId: listId, request))
        } catch let error as APIError where error.httpStatusCode == 403 {
            // The server is the real subscriber gate today — see the TODO on
            // `requireListManagement()`. Project its 403 onto the domain error
            // the sharing UI already renders as an upsell.
            throw ListsError.subscriberRequired
        }
    }

    public func watch(listId: String) async throws {
        // No `userId` — the self-subscribe branch. No entitlement check either:
        // watching a public list is free, and gating it would make the Watch
        // button on a public profile an upsell for something the web gives away.
        _ = try await api.send(Lists.addWatcher(listId: listId, AddListWatcherRequest()))
    }

    // MARK: - M3 watchers

    public func watchers(of listId: String) async throws -> [ListWatcher] {
        // Reading who watches a list is free on every tier (#40 matrix:
        // creation is gated, inspection is not).
        let response = try await api.send(Lists.watchers(listId: listId))
        return response.watchers.map(ListWatcher.init(from:))
    }

    public func myWatcherStatus(of listId: String) async throws -> WatcherStatus {
        let dto = try await api.send(Lists.myWatcherStatus(listId: listId))
        return WatcherStatus(from: dto)
    }

    public func watcherCandidates(
        of listId: String,
        search: String?,
        limit: Int
    ) async throws -> [CollaboratorCandidate] {
        // Listing who *could* be added is a read; the gate lives on
        // `addWatcher`, the action that actually shares the list.
        // Blank searches are sent as `nil` so the route returns its default
        // (unfiltered) candidate page rather than matching on an empty string.
        let trimmed = search?.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = try await api.send(
            Lists.watcherCandidates(
                listId: listId,
                search: (trimmed?.isEmpty ?? true) ? nil : trimmed,
                limit: limit
            )
        )
        return response.users.map {
            CollaboratorCandidate(
                id: $0.id,
                username: $0.username,
                displayName: $0.displayName,
                email: $0.email,
                avatar: $0.avatar.flatMap(URL.init(string:))
            )
        }
    }

    public func setWatcher(
        listId: String,
        userId: String,
        role: WatcherRole
    ) async throws -> ListWatcher {
        let request = UpdateListWatcherRequest(role: role.wireToken)
        do {
            // The route answers `{ role }` only, so the caller's own `userId`
            // completes the row. The server echoes the role it actually
            // applied; we prefer that over the requested one.
            let response = try await api.send(Lists.setWatcher(listId: listId, userId: userId, request))
            let applied = response.role.map(WatcherRole.init(wireToken:)) ?? role
            return ListWatcher(userId: userId, role: applied)
        } catch let error as APIError where error.httpStatusCode == 403 {
            // Role changes are subscriber-gated exactly like add-watcher.
            throw ListsError.subscriberRequired
        }
    }

    public func removeWatcher(listId: String, userId: String) async throws {
        try await api.sendVoid(Lists.removeWatcher(listId: listId, userId: userId))
    }

    // MARK: - M3 connections

    public func connections(of listId: String?) async throws -> [ListConnection] {
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
        let request = CreateListConnectionRequest(
            fromListId: fromListId,
            toListId: toListId,
            label: label
        )
        let dto = try await api.send(Lists.createConnection(request))
        return ListConnection(from: dto)
    }

    public func removeConnection(connectionId: String) async throws {
        try await api.sendVoid(Lists.deleteConnection(id: connectionId))
    }

    // MARK: - Internals

    /// The subscriber gate for list **creation**, and only creation.
    ///
    /// Throws `ListsError.subscriberRequired` before any HTTP call when the
    /// account may not create lists. Reads, edits, row CRUD, watchers, and
    /// connections deliberately do not call this (GitHub #40).
    ///
    /// **Why this is not applied wholesale.** Before #40 this one seam guarded
    /// *every* write method — 24 call sites on `dev`, including pure reads.
    /// `canManageLists` was permissive-by-default (`?? true`), so that was
    /// harmless; tightening it without first removing the read call sites would
    /// have stopped free users reading their own lists. #40 removes those call
    /// sites, so the gate can now be honest.
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
