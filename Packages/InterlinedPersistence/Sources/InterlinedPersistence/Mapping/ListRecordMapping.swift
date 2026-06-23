import Foundation
import InterlinedDomain

/// Internal mapping between SwiftData list records and the domain value
/// types. Mirrors the `MessageRecordMapping` pattern: callers consume
/// `OwnedList` / `ListRow` / `ListSchema` values across the actor boundary
/// and never see `@Model` types directly.

// MARK: - ListRecord ↔ OwnedList

extension ListRecord {

    convenience init(from list: OwnedList) {
        self.init(
            id: list.id,
            title: list.title,
            listDescription: list.description,
            publiclyVisible: list.visibility.isPubliclyVisible,
            schemaDescription: list.schemaDescription,
            parentID: list.parentID,
            gitHubRepository: list.gitHubSource?.repository,
            gitHubPath: list.gitHubSource?.path,
            gitHubBranch: list.gitHubSource?.branch,
            gitHubLastRefreshedAt: list.gitHubSource?.lastRefreshedAt,
            gitHubRefreshStatus: list.gitHubSource?.refreshStatus,
            createdAt: list.createdAt,
            updatedAt: list.updatedAt
        )
    }

    /// Copy fresh field values from a domain `OwnedList`. Must touch every
    /// mutable field so stale data never leaks through.
    func apply(_ list: OwnedList) {
        title = list.title
        listDescription = list.description
        publiclyVisible = list.visibility.isPubliclyVisible
        schemaDescription = list.schemaDescription
        parentID = list.parentID
        gitHubRepository = list.gitHubSource?.repository
        gitHubPath = list.gitHubSource?.path
        gitHubBranch = list.gitHubSource?.branch
        gitHubLastRefreshedAt = list.gitHubSource?.lastRefreshedAt
        gitHubRefreshStatus = list.gitHubSource?.refreshStatus
        createdAt = list.createdAt
        updatedAt = list.updatedAt
    }

    /// Hydrate a domain `OwnedList` from this record.
    func toOwnedList() -> OwnedList {
        let source: GitHubListSource? = {
            // Build a GitHubListSource only if at least one field is set.
            if gitHubRepository == nil,
               gitHubPath == nil,
               gitHubBranch == nil,
               gitHubLastRefreshedAt == nil,
               gitHubRefreshStatus == nil {
                return nil
            }
            return GitHubListSource(
                repository: gitHubRepository,
                path: gitHubPath,
                branch: gitHubBranch,
                lastRefreshedAt: gitHubLastRefreshedAt,
                refreshStatus: gitHubRefreshStatus
            )
        }()
        return OwnedList(
            id: id,
            title: title,
            description: listDescription,
            visibility: Visibility(publiclyVisible: publiclyVisible),
            schemaDescription: schemaDescription,
            parentID: parentID,
            gitHubSource: source,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - ListSchemaRecord / SchemaFieldRecord ↔ ListSchema

extension ListSchemaRecord {

    convenience init(listID: String, schema: ListSchema) {
        let fieldRecords = schema.fields.enumerated().map { index, field in
            SchemaFieldRecord(
                position: index,
                name: field.name,
                typeToken: field.type.dslToken,
                nullable: field.nullable,
                enumValues: field.enumValues
            )
        }
        self.init(listID: listID, fields: fieldRecords)
    }

    /// Hydrate the typed schema. Field records out of `SchemaFieldType`'s
    /// closed set are dropped silently — the cache is best-effort.
    func toListSchema() -> ListSchema {
        let ordered = fields.sorted(by: { $0.position < $1.position })
        let domain: [SchemaField] = ordered.compactMap { record in
            guard let type = SchemaFieldType(dslToken: record.typeToken) else {
                return nil
            }
            return SchemaField(
                name: record.name,
                type: type,
                nullable: record.nullable,
                enumValues: record.enumValues
            )
        }
        return ListSchema(fields: domain)
    }
}

// MARK: - ListRowRecord ↔ ListRow

extension ListRowRecord {

    convenience init(from row: ListRow, listID: String, position: Int) {
        let data = (try? RowDataCodec.encode(row.fields)) ?? Data("{}".utf8)
        self.init(
            id: row.id,
            listID: listID,
            rowDataJSON: data,
            position: position,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt
        )
    }

    func apply(_ row: ListRow, position: Int) {
        let data = (try? RowDataCodec.encode(row.fields)) ?? Data("{}".utf8)
        rowDataJSON = data
        self.position = position
        createdAt = row.createdAt
        updatedAt = row.updatedAt
    }

    func toListRow() -> ListRow {
        let fields = (try? RowDataCodec.decode(rowDataJSON)) ?? [:]
        return ListRow(
            id: id,
            listID: listID,
            fields: fields,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - ListConnectionRecord ↔ ListConnection

extension ListConnectionRecord {

    convenience init(from connection: ListConnection) {
        self.init(
            id: connection.id,
            fromListID: connection.fromListId,
            toListID: connection.toListId,
            label: connection.label,
            createdAt: connection.createdAt
        )
    }

    func toListConnection() -> ListConnection {
        ListConnection(
            id: id,
            fromListId: fromListID,
            toListId: toListID,
            label: label,
            createdAt: createdAt
        )
    }
}

// MARK: - ListWatcherRecord ↔ ListWatcher

extension ListWatcherRecord {

    convenience init(from watcher: ListWatcher, listID: String) {
        self.init(
            listID: listID,
            userID: watcher.userId,
            username: watcher.username,
            roleToken: watcher.role.wireToken,
            createdAt: watcher.createdAt
        )
    }

    func toListWatcher() -> ListWatcher {
        ListWatcher(
            userId: userID,
            username: username,
            role: WatcherRole(wireToken: roleToken),
            createdAt: createdAt
        )
    }
}
