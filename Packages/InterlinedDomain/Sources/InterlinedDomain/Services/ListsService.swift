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

    /// A saved-view create, rename or fork supplied a blank name. Raised before
    /// any HTTP call: the views routes do not reject an empty `name`, so the
    /// round-trip would succeed and leave an unlabelled row in a picker the
    /// user then cannot tell apart from the next one
    /// (work-consolidation.md G40).
    case invalidViewName

    /// A schema rebuild would drop a column that still holds row data, and the
    /// server refused it pending confirmation. Re-submit with `force: true` to
    /// accept the data loss.
    ///
    /// Carries the server's own sentence rather than a client-written one: the
    /// server names the situation accurately and the column list it also sends
    /// is not reachable from here (see `updateSchema(of:schema:force:)`).
    case schemaChangeWouldLoseData(serverMessage: String?)
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
        case .invalidViewName:
            return "Give this view a name."
        case .schemaChangeWouldLoseData(let serverMessage):
            return serverMessage
                ?? "This change would delete columns that still hold data. Confirm to continue."
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
        schema: ListSchema?,
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
    /// Rebuilds a list's columns.
    ///
    /// - Parameter force: confirms a destructive change. Without it the server
    ///   refuses to drop a column that still holds row data, and the call throws
    ///   `ListsError.schemaChangeWouldLoseData`.
    func updateSchema(of listId: String, schema: ListSchema, force: Bool) async throws -> ListSchema

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

    // MARK: - G40 saved views

    /// Loads every saved view on a list: the list's **shared** views plus the
    /// caller's **personal** ones, in the server's array order.
    ///
    /// Unpaged, and deliberately not sorted client-side — `position` repeats
    /// across scope buckets, so re-sorting on it would shuffle the two sets
    /// together (work-consolidation.md G40).
    func savedViews(of listId: String) async throws -> [SavedListView]

    /// Creates a saved view. Throws `ListsError.invalidViewName` on a blank
    /// name before any HTTP call.
    ///
    /// Free on every tier — the views routes are `x-subscription-tier: free`.
    func createSavedView(
        listId: String,
        name: String,
        scope: SavedListViewScope,
        config: SavedListViewConfig,
        isDefault: Bool
    ) async throws -> SavedListView

    /// Updates a saved view's name, arrangement and/or default flag. `nil`
    /// leaves that field untouched.
    ///
    /// - Important: a non-nil `config` **replaces** the stored arrangement
    ///   whole, so pass the complete config you want to end up with. The
    ///   parameter takes a `SavedListViewConfig`, which cannot be partial, so
    ///   this is enforced by the type rather than by the caller remembering.
    func updateSavedView(
        listId: String,
        viewId: String,
        name: String?,
        config: SavedListViewConfig?,
        isDefault: Bool?
    ) async throws -> SavedListView

    /// Deletes a saved view.
    func deleteSavedView(listId: String, viewId: String) async throws

    /// Forks a view into a personal copy owned by the caller — the spec's
    /// "escape hatch" from the list owner's arrangement.
    ///
    /// Works on a personal source view too, not only a shared one (verified
    /// live 2026-09-15), so the UI may offer it as plain "duplicate". A `nil`
    /// name lets the server pick one; a supplied-but-blank name throws
    /// `ListsError.invalidViewName`.
    func forkSavedView(
        listId: String,
        viewId: String,
        name: String?
    ) async throws -> SavedListView
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
        let response = try await api.send(Lists.publicList(username: username, id: slug))
        return ListDetail(from: response.list)
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
        let response = try await api.send(Lists.get(id: listId))
        return OwnedList(from: response.data)
    }

    /// Creates a list, optionally with its columns.
    ///
    /// `schema` used to be the client's DSL **string**, which the server rejects
    /// outright (`400 "Invalid schema: DSL must be an object"`) — so a list with
    /// columns could never be created from macOS (GitHub #85). It is now the
    /// parsed `ListSchema`, serialised to the object the server wants.
    ///
    /// Callers that hold a DSL string parse it first: `SchemaDSL.parse` is still
    /// how the New List sheet turns what the user typed into columns. The DSL
    /// remains an authoring convenience; it is no longer a wire format.
    public func create(
        title: String,
        description: String?,
        schema: ListSchema?,
        parentId: String?,
        isPublic: Bool
    ) async throws -> OwnedList {
        try requireListManagement()
        let request = CreateListRequest(
            title: title,
            description: description,
            // An empty schema is not a schema: sending `{fields: []}` would ask
            // the server to create a column-less list explicitly, where omitting
            // the key lets it apply its own default.
            schema: (schema?.fields.isEmpty == false)
                ? schema?.asDTO(name: title, description: description)
                : nil,
            parentId: parentId,
            isPublic: isPublic
        )
        let response = try await api.send(Lists.create(request))
        return OwnedList(from: response.data)
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
        let response = try await api.send(Lists.update(id: listId, request))
        return OwnedList(from: response.data)
    }

    public func delete(listId: String) async throws {
        try await api.sendVoid(Lists.delete(id: listId))
    }

    // MARK: - M3 schema

    /// Reads a list's columns.
    ///
    /// The response is the schema **object**; there is no DSL string to parse
    /// and therefore no `malformedSchema` failure mode on this path any more —
    /// an unrecognised column type degrades to `.text` rather than failing the
    /// whole schema (see `SchemaField.init(dto:)`).
    public func schema(of listId: String) async throws -> ListSchema {
        let response = try await api.send(Lists.schema(id: listId))
        return ListSchema(dto: response.data)
    }

    /// Rebuilds a list's columns.
    ///
    /// - Parameter force: confirms a destructive change. The server refuses to
    ///   drop a column that still holds row data unless this is set, answering
    ///   `400` with the affected column keys — surfaced as
    ///   `ListsError.schemaChangeWouldLoseData` so the UI can name them and ask,
    ///   rather than showing a bare "Bad Request" for what is really a question.
    public func updateSchema(
        of listId: String,
        schema: ListSchema,
        force: Bool = false
    ) async throws -> ListSchema {
        let request = UpdateListSchemaRequest(schema: schema.asDTO(name: nil))
        do {
            let response = try await api.send(Lists.updateSchema(id: listId, request, force: force))
            // The write answers the list plus its stored columns, so the result
            // is read back from `properties` rather than re-fetching.
            if let fields = response.data.schemaFields {
                return ListSchema(fields: fields.map(SchemaField.init(dto:)))
            }
            return schema
        } catch let error as APIError {
            // The server refuses a destructive rebuild with `400` plus a
            // `propertiesWithData` array naming the columns that still hold
            // data. Re-badge it so the UI can offer the confirmation instead of
            // showing a bare "Bad Request" for what is really a question.
            //
            // The column list is **not** available here: `APIError.badRequest`
            // carries only the decoded `{error}` string, so the rest of the body
            // is discarded before this point. `ListSchemaConflictDTO` models the
            // full shape and this becomes a one-line change once the kit keeps
            // the body — filed as its own issue rather than worked around with a
            // second request that could race the first.
            if case .badRequest(let message) = error, !force {
                throw ListsError.schemaChangeWouldLoseData(serverMessage: message)
            }
            throw error
        }
    }

    // MARK: - M3 refresh

    public func refresh(listId: String) async throws -> OwnedList {
        let response = try await api.send(Lists.refresh(id: listId))
        return OwnedList(from: response.data)
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

    // MARK: - G40 saved views

    /// Free on every tier: the five views routes are declared
    /// `x-subscription-tier: free` and were all reached live on a free account
    /// with a Bearer token (2026-09-15). No `requireListManagement()` call
    /// belongs on any of them — arranging a list you can already read is not
    /// creating one (GitHub #40 matrix).
    public func savedViews(of listId: String) async throws -> [SavedListView] {
        let response = try await api.send(Lists.views(listId: listId))
        // Server order, verbatim. See the protocol doc for why `position` is
        // not a sort key.
        return response.views.map(SavedListView.init(from:))
    }

    public func createSavedView(
        listId: String,
        name: String,
        scope: SavedListViewScope,
        config: SavedListViewConfig,
        isDefault: Bool
    ) async throws -> SavedListView {
        let trimmed = try requireViewName(name)
        let request = CreateListViewRequest(
            name: trimmed,
            // `scope` is the one field the server validates — an unknown token
            // is a hard 400 — so it is sent from the closed domain enum rather
            // than from any caller-supplied string.
            scope: scope.rawValue,
            config: config.wireValue,
            isDefault: isDefault
        )
        let response = try await api.send(Lists.createView(listId: listId, request))
        // Believe the server's row, not the optimistic local one: unknown
        // `mode` / `density` values and every filter are silently normalised on
        // write, so the request and the stored view routinely disagree.
        return SavedListView(from: response.view)
    }

    public func updateSavedView(
        listId: String,
        viewId: String,
        name: String?,
        config: SavedListViewConfig?,
        isDefault: Bool?
    ) async throws -> SavedListView {
        // A supplied name must be meaningful; an absent one means "don't
        // touch the name", which is a different thing entirely.
        let trimmedName = try name.map(requireViewName)
        let request = UpdateListViewRequest(
            name: trimmedName,
            config: config?.wireValue,
            isDefault: isDefault
        )
        let response = try await api.send(Lists.updateView(listId: listId, viewId: viewId, request))
        return SavedListView(from: response.view)
    }

    public func deleteSavedView(listId: String, viewId: String) async throws {
        try await api.sendVoid(Lists.deleteView(listId: listId, viewId: viewId))
    }

    public func forkSavedView(
        listId: String,
        viewId: String,
        name: String?
    ) async throws -> SavedListView {
        let trimmedName = try name.map(requireViewName)
        let response = try await api.send(
            Lists.forkView(listId: listId, viewId: viewId, ForkListViewRequest(name: trimmedName))
        )
        return SavedListView(from: response.view)
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

    /// Trims a saved-view name and rejects a blank one before any HTTP call.
    ///
    /// The route accepts `""` happily, so the server will not catch this: a
    /// blank create lands an unlabelled row in the views picker that the user
    /// cannot tell apart from the next blank one, and cannot rename without
    /// first identifying. Cheaper to refuse here (work-consolidation.md G40).
    private func requireViewName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ListsError.invalidViewName }
        return trimmed
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

// The `ListCellValue` → `ListJSONValue` projection this file uses when writing
// rows moved to `ListMappers.swift`, next to its inverse. It was `fileprivate`
// here, which stopped the schema mappers reusing it for a column's
// `defaultValue` (GitHub #85) and left saved-view filters without one at all
// (G40).
