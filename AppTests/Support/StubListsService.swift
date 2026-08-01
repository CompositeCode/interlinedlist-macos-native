// StubListsService
//
// Deterministic `ListsServicing` stub for App-layer view-model tests
// of the M3 Lists feature. Mirrors `StubMessagesService`: an actor
// with a queued outcome list per call site and a recorded-call log.
//
// Only the entry points the Wave 4.3 view models exercise are
// implemented; the rest throw a `notProgrammed` error so a test
// hitting an unprepared path fails loudly.

import Foundation
import InterlinedDomain

struct RecordedListsCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case publicLists(username: String, limit: Int, offset: Int)
        case publicList(username: String, slug: String)
        case publicRows(username: String, slug: String, limit: Int, offset: Int)
        case myLists(limit: Int, offset: Int)
        case detail(listId: String)
        case create(title: String, description: String?, schema: String?, parentId: String?, isPublic: Bool)
        case update(listId: String, title: String?, description: String?, isPublic: Bool?, parentId: String?)
        case delete(listId: String)
        case schema(listId: String)
        case updateSchema(listId: String, fieldsCount: Int)
        case refresh(listId: String)
        case rows(listId: String, limit: Int, offset: Int)
        case row(listId: String, rowId: String)
        case createRow(listId: String, fieldsCount: Int)
        case updateRow(listId: String, rowId: String, fieldsCount: Int)
        case deleteRow(listId: String, rowId: String)
        case watchers(listId: String)
        case myWatcherStatus(listId: String)
        case watcherUsers(listId: String)
        case setWatcher(listId: String, userId: String, role: WatcherRole)
        case removeWatcher(listId: String, userId: String)
        case connections(listId: String?)
        case addConnection(from: String, to: String, label: String?)
        case removeConnection(id: String)
    }
    let kind: Kind
}

actor StubListsService: ListsServicing {

    // MARK: Outcome queues
    private var myListsOutcomes: [Result<OwnedListsPage, Error>] = []
    private var createOutcomes: [Result<OwnedList, Error>] = []
    private var updateOutcomes: [Result<OwnedList, Error>] = []
    private var deleteOutcomes: [Result<Void, Error>] = []
    private var detailOutcomes: [Result<OwnedList, Error>] = []
    private var schemaOutcomes: [Result<ListSchema, Error>] = []
    private var updateSchemaOutcomes: [Result<ListSchema, Error>] = []
    private var refreshOutcomes: [Result<OwnedList, Error>] = []
    private var rowsOutcomes: [Result<RowsPage, Error>] = []
    private var rowOutcomes: [Result<ListRow, Error>] = []
    private var createRowOutcomes: [Result<ListRow, Error>] = []
    private var updateRowOutcomes: [Result<ListRow, Error>] = []
    private var deleteRowOutcomes: [Result<Void, Error>] = []
    private var watchersOutcomes: [Result<[ListWatcher], Error>] = []
    private var watcherUsersOutcomes: [Result<[ListWatcher], Error>] = []
    private var myWatcherStatusOutcomes: [Result<WatcherStatus, Error>] = []
    private var setWatcherOutcomes: [Result<ListWatcher, Error>] = []
    private var removeWatcherOutcomes: [Result<Void, Error>] = []
    private var connectionsOutcomes: [Result<[ListConnection], Error>] = []
    private var addConnectionOutcomes: [Result<ListConnection, Error>] = []
    private var removeConnectionOutcomes: [Result<Void, Error>] = []

    private(set) var recorded: [RecordedListsCall] = []

    /// The full `ListSchema` passed to the most recent `updateSchema` call.
    /// The recorded-call log only captures `fieldsCount`; tests that need to
    /// assert per-field detail (e.g. a `select` column's `enumValues` round-
    /// tripping through save) read this instead.
    private(set) var lastUpdatedSchema: ListSchema?

    // MARK: Programmable enqueue helpers
    func enqueueMyLists(success page: OwnedListsPage) { myListsOutcomes.append(.success(page)) }
    func enqueueMyLists(failure error: Error) { myListsOutcomes.append(.failure(error)) }

    func enqueueCreate(success list: OwnedList) { createOutcomes.append(.success(list)) }
    func enqueueCreate(failure error: Error) { createOutcomes.append(.failure(error)) }

    func enqueueUpdate(success list: OwnedList) { updateOutcomes.append(.success(list)) }
    func enqueueUpdate(failure error: Error) { updateOutcomes.append(.failure(error)) }

    func enqueueDeleteSuccess() { deleteOutcomes.append(.success(())) }
    func enqueueDelete(failure error: Error) { deleteOutcomes.append(.failure(error)) }

    func enqueueDetail(success list: OwnedList) { detailOutcomes.append(.success(list)) }

    func enqueueSchema(success schema: ListSchema) { schemaOutcomes.append(.success(schema)) }
    func enqueueSchema(failure error: Error) { schemaOutcomes.append(.failure(error)) }

    func enqueueUpdateSchema(success schema: ListSchema) { updateSchemaOutcomes.append(.success(schema)) }
    func enqueueUpdateSchema(failure error: Error) { updateSchemaOutcomes.append(.failure(error)) }

    func enqueueRefresh(success list: OwnedList) { refreshOutcomes.append(.success(list)) }
    func enqueueRefresh(failure error: Error) { refreshOutcomes.append(.failure(error)) }

    func enqueueRows(success page: RowsPage) { rowsOutcomes.append(.success(page)) }
    func enqueueRows(failure error: Error) { rowsOutcomes.append(.failure(error)) }

    func enqueueRow(success row: ListRow) { rowOutcomes.append(.success(row)) }

    func enqueueCreateRow(success row: ListRow) { createRowOutcomes.append(.success(row)) }
    func enqueueCreateRow(failure error: Error) { createRowOutcomes.append(.failure(error)) }

    func enqueueUpdateRow(success row: ListRow) { updateRowOutcomes.append(.success(row)) }
    func enqueueUpdateRow(failure error: Error) { updateRowOutcomes.append(.failure(error)) }

    func enqueueDeleteRowSuccess() { deleteRowOutcomes.append(.success(())) }
    func enqueueDeleteRow(failure error: Error) { deleteRowOutcomes.append(.failure(error)) }

    func enqueueWatchers(success watchers: [ListWatcher]) { watchersOutcomes.append(.success(watchers)) }
    func enqueueWatcherUsers(success watchers: [ListWatcher]) { watcherUsersOutcomes.append(.success(watchers)) }
    func enqueueWatcherUsers(failure error: Error) { watcherUsersOutcomes.append(.failure(error)) }
    func enqueueMyWatcherStatus(success status: WatcherStatus) { myWatcherStatusOutcomes.append(.success(status)) }

    func enqueueSetWatcher(success watcher: ListWatcher) { setWatcherOutcomes.append(.success(watcher)) }
    func enqueueSetWatcher(failure error: Error) { setWatcherOutcomes.append(.failure(error)) }
    func enqueueRemoveWatcherSuccess() { removeWatcherOutcomes.append(.success(())) }
    func enqueueRemoveWatcher(failure error: Error) { removeWatcherOutcomes.append(.failure(error)) }

    func enqueueConnections(success edges: [ListConnection]) { connectionsOutcomes.append(.success(edges)) }
    func enqueueConnections(failure error: Error) { connectionsOutcomes.append(.failure(error)) }
    func enqueueAddConnection(success edge: ListConnection) { addConnectionOutcomes.append(.success(edge)) }
    func enqueueAddConnection(failure error: Error) { addConnectionOutcomes.append(.failure(error)) }
    func enqueueRemoveConnectionSuccess() { removeConnectionOutcomes.append(.success(())) }
    func enqueueRemoveConnection(failure error: Error) { removeConnectionOutcomes.append(.failure(error)) }

    // MARK: ListsServicing — public browse

    func publicLists(username: String, limit: Int, offset: Int) async throws -> ListsPage {
        recorded.append(.init(kind: .publicLists(username: username, limit: limit, offset: offset)))
        throw StubError.notProgrammed("publicLists")
    }

    func publicList(username: String, slug: String) async throws -> ListDetail {
        recorded.append(.init(kind: .publicList(username: username, slug: slug)))
        throw StubError.notProgrammed("publicList")
    }

    func publicRows(username: String, slug: String, limit: Int, offset: Int) async throws -> RowsPage {
        recorded.append(.init(kind: .publicRows(username: username, slug: slug, limit: limit, offset: offset)))
        throw StubError.notProgrammed("publicRows")
    }

    // MARK: ListsServicing — owned CRUD

    func myLists(limit: Int, offset: Int) async throws -> OwnedListsPage {
        recorded.append(.init(kind: .myLists(limit: limit, offset: offset)))
        return try take(&myListsOutcomes, label: "myLists")
    }

    func detail(listId: String) async throws -> OwnedList {
        recorded.append(.init(kind: .detail(listId: listId)))
        return try take(&detailOutcomes, label: "detail")
    }

    func create(title: String, description: String?, schema: String?, parentId: String?, isPublic: Bool) async throws -> OwnedList {
        recorded.append(.init(kind: .create(title: title, description: description, schema: schema, parentId: parentId, isPublic: isPublic)))
        return try take(&createOutcomes, label: "create")
    }

    func update(listId: String, title: String?, description: String?, isPublic: Bool?, parentId: String?) async throws -> OwnedList {
        recorded.append(.init(kind: .update(listId: listId, title: title, description: description, isPublic: isPublic, parentId: parentId)))
        return try take(&updateOutcomes, label: "update")
    }

    func delete(listId: String) async throws {
        recorded.append(.init(kind: .delete(listId: listId)))
        let _: Void = try take(&deleteOutcomes, label: "delete")
    }

    // MARK: ListsServicing — schema

    func schema(of listId: String) async throws -> ListSchema {
        recorded.append(.init(kind: .schema(listId: listId)))
        return try take(&schemaOutcomes, label: "schema")
    }

    func updateSchema(of listId: String, schema: ListSchema) async throws -> ListSchema {
        recorded.append(.init(kind: .updateSchema(listId: listId, fieldsCount: schema.fields.count)))
        lastUpdatedSchema = schema
        return try take(&updateSchemaOutcomes, label: "updateSchema")
    }

    // MARK: ListsServicing — refresh

    func refresh(listId: String) async throws -> OwnedList {
        recorded.append(.init(kind: .refresh(listId: listId)))
        return try take(&refreshOutcomes, label: "refresh")
    }

    // MARK: ListsServicing — row CRUD

    func rows(of listId: String, limit: Int, offset: Int) async throws -> RowsPage {
        recorded.append(.init(kind: .rows(listId: listId, limit: limit, offset: offset)))
        return try take(&rowsOutcomes, label: "rows")
    }

    func row(listId: String, rowId: String) async throws -> ListRow {
        recorded.append(.init(kind: .row(listId: listId, rowId: rowId)))
        return try take(&rowOutcomes, label: "row")
    }

    func createRow(listId: String, data: [String: ListCellValue]) async throws -> ListRow {
        recorded.append(.init(kind: .createRow(listId: listId, fieldsCount: data.count)))
        return try take(&createRowOutcomes, label: "createRow")
    }

    func updateRow(listId: String, rowId: String, data: [String: ListCellValue]) async throws -> ListRow {
        recorded.append(.init(kind: .updateRow(listId: listId, rowId: rowId, fieldsCount: data.count)))
        return try take(&updateRowOutcomes, label: "updateRow")
    }

    func deleteRow(listId: String, rowId: String) async throws {
        recorded.append(.init(kind: .deleteRow(listId: listId, rowId: rowId)))
        let _: Void = try take(&deleteRowOutcomes, label: "deleteRow")
    }

    // MARK: ListsServicing — watchers

    func watchers(of listId: String) async throws -> [ListWatcher] {
        recorded.append(.init(kind: .watchers(listId: listId)))
        return try take(&watchersOutcomes, label: "watchers")
    }

    func myWatcherStatus(of listId: String) async throws -> WatcherStatus {
        recorded.append(.init(kind: .myWatcherStatus(listId: listId)))
        return try take(&myWatcherStatusOutcomes, label: "myWatcherStatus")
    }

    func watcherUsers(of listId: String) async throws -> [ListWatcher] {
        recorded.append(.init(kind: .watcherUsers(listId: listId)))
        return try take(&watcherUsersOutcomes, label: "watcherUsers")
    }

    func setWatcher(listId: String, userId: String, role: WatcherRole) async throws -> ListWatcher {
        recorded.append(.init(kind: .setWatcher(listId: listId, userId: userId, role: role)))
        return try take(&setWatcherOutcomes, label: "setWatcher")
    }

    func removeWatcher(listId: String, userId: String) async throws {
        recorded.append(.init(kind: .removeWatcher(listId: listId, userId: userId)))
        let _: Void = try take(&removeWatcherOutcomes, label: "removeWatcher")
    }

    // MARK: ListsServicing — connections

    func connections(of listId: String?) async throws -> [ListConnection] {
        recorded.append(.init(kind: .connections(listId: listId)))
        return try take(&connectionsOutcomes, label: "connections")
    }

    func addConnection(fromListId: String, toListId: String, label: String?) async throws -> ListConnection {
        recorded.append(.init(kind: .addConnection(from: fromListId, to: toListId, label: label)))
        return try take(&addConnectionOutcomes, label: "addConnection")
    }

    func removeConnection(connectionId: String) async throws {
        recorded.append(.init(kind: .removeConnection(id: connectionId)))
        let _: Void = try take(&removeConnectionOutcomes, label: "removeConnection")
    }

    // MARK: - Internals

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else { throw StubError.notProgrammed(label) }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubError: Error, Equatable {
        case notProgrammed(String)
    }
}

// MARK: - Convenience fixtures

enum ListsFixtures {
    static func ownedList(
        id: String,
        title: String = "List",
        description: String? = nil,
        visibility: Visibility = .private,
        parentID: String? = nil,
        gitHubSource: GitHubListSource? = nil
    ) -> OwnedList {
        OwnedList(
            id: id,
            title: title,
            description: description,
            visibility: visibility,
            schemaDescription: nil,
            parentID: parentID,
            gitHubSource: gitHubSource,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func ownedListsPage(_ lists: [OwnedList], hasMore: Bool = false, nextOffset: Int? = nil) -> OwnedListsPage {
        OwnedListsPage(lists: lists, hasMore: hasMore, nextOffset: nextOffset)
    }

    static func row(
        id: String,
        listId: String = "L1",
        fields: [String: ListCellValue] = [:]
    ) -> ListRow {
        ListRow(
            id: id,
            listID: listId,
            fields: fields,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func watcher(
        userId: String,
        username: String? = nil,
        role: WatcherRole = .viewer
    ) -> ListWatcher {
        ListWatcher(userId: userId, username: username, role: role)
    }

    static func connection(
        id: String,
        from: String,
        to: String,
        label: String? = nil
    ) -> ListConnection {
        ListConnection(id: id, fromListId: from, toListId: to, label: label)
    }
}
