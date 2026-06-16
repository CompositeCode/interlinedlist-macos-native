import Foundation

// MARK: - ListJSONValue

/// A flexible, type-erased JSON value used to model **dynamic-schema list row
/// data**.
///
/// List rows are not fixed structs: each list defines its own schema DSL
/// (`"Title:text, Year:number, Read:boolean"`), so the `rowData` payload is a
/// `[fieldName: value]` map whose value types vary per column and per list.
/// Modelling `rowData` as `[String: ListJSONValue]` lets the kit decode and
/// re-encode any row losslessly without knowing the schema ahead of time —
/// the Domain layer interprets the values against the parsed schema.
///
/// Named with a `List` prefix to avoid clashing with the kit-private
/// `JSONValue` used by `PaginatedDecoder` and with any other group's helper.
public enum ListJSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ListJSONValue])
    case object([String: ListJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([ListJSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: ListJSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value in list row data"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

public extension ListJSONValue {
    /// Convenience reader for the common case of a string-valued cell.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

// MARK: - ListDTO

/// A structured list. Fields are modelled `1:1` against the API response
/// (`https://interlinedlist.com/help/api`). Optional where the API only
/// returns the field on some routes (e.g. `schema`/`description` come back on
/// detail/create responses but not the lightweight collection rows).
public struct ListDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    public let isPublic: Bool?
    /// The schema DSL string (e.g. `"Title:text, Year:number"`). Present on
    /// detail and create responses.
    public let schema: String?
    /// Parent list id for nested lists.
    public let parentId: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        title: String,
        description: String? = nil,
        isPublic: Bool? = nil,
        schema: String? = nil,
        parentId: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.isPublic = isPublic
        self.schema = schema
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - List schema

/// Response of `GET /api/lists/[id]/schema` and `PUT /api/lists/[id]/schema`:
/// `{ "schema": "<DSL>" }`.
public struct ListSchemaDTO: Codable, Sendable, Equatable {
    public let schema: String

    public init(schema: String) {
        self.schema = schema
    }
}

// MARK: - List rows

/// A single dynamic-schema list row. `rowData` is the flexible field map keyed
/// by the schema's column names; its value types are list-defined.
public struct ListRowDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let listId: String?
    public let rowData: [String: ListJSONValue]
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        listId: String? = nil,
        rowData: [String: ListJSONValue],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.listId = listId
        self.rowData = rowData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - List watchers

/// A watcher / access entry on a shared list. Role is a free string from the
/// API (`"watcher"`, `"collaborator"`, `"manager"`, …); the Domain layer maps
/// it to a typed role. Fields beyond `userId`/`role` are optional because the
/// API reference does not pin them down on every watcher route.
public struct ListWatcherDTO: Codable, Sendable, Equatable {
    public let userId: String
    public let role: String?
    public let username: String?
    public let createdAt: Date?

    public init(
        userId: String,
        role: String? = nil,
        username: String? = nil,
        createdAt: Date? = nil
    ) {
        self.userId = userId
        self.role = role
        self.username = username
        self.createdAt = createdAt
    }
}

/// Response of `GET /api/lists/[id]/watchers/me` — the caller's own watcher
/// status on a list. Modelled tolerantly: `isWatching` plus the optional role.
public struct ListWatcherStatusDTO: Codable, Sendable, Equatable {
    public let isWatching: Bool?
    public let role: String?

    public init(isWatching: Bool? = nil, role: String? = nil) {
        self.isWatching = isWatching
        self.role = role
    }
}

// MARK: - List connections

/// A directed connection between two lists (powers the ERD / graph canvas).
public struct ListConnectionDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let fromListId: String
    public let toListId: String
    public let label: String?
    public let createdAt: Date?

    public init(
        id: String,
        fromListId: String,
        toListId: String,
        label: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.fromListId = fromListId
        self.toListId = toListId
        self.label = label
        self.createdAt = createdAt
    }
}

/// `GET /api/lists/connections` wraps its array under `"connections"`.
public struct ListConnectionsResponse: Codable, Sendable, Equatable {
    public let connections: [ListConnectionDTO]

    public init(connections: [ListConnectionDTO]) {
        self.connections = connections
    }
}

// MARK: - Request bodies

/// `POST /api/lists` body.
public struct CreateListRequest: Codable, Sendable, Equatable {
    public let title: String
    public let description: String?
    public let schema: String?
    public let parentId: String?
    public let isPublic: Bool?

    public init(
        title: String,
        description: String? = nil,
        schema: String? = nil,
        parentId: String? = nil,
        isPublic: Bool? = nil
    ) {
        self.title = title
        self.description = description
        self.schema = schema
        self.parentId = parentId
        self.isPublic = isPublic
    }
}

/// `PUT /api/lists/[id]` body. All fields optional — metadata partial update.
public struct UpdateListRequest: Codable, Sendable, Equatable {
    public let title: String?
    public let description: String?
    public let isPublic: Bool?
    public let parentId: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        isPublic: Bool? = nil,
        parentId: String? = nil
    ) {
        self.title = title
        self.description = description
        self.isPublic = isPublic
        self.parentId = parentId
    }
}

/// `PUT /api/lists/[id]/schema` body: `{ "schema": "<DSL>" }`.
public struct UpdateListSchemaRequest: Codable, Sendable, Equatable {
    public let schema: String

    public init(schema: String) {
        self.schema = schema
    }
}

/// `POST /api/lists/[id]/data` body: `{ "rowData": { ... } }`.
public struct CreateListRowRequest: Codable, Sendable, Equatable {
    public let rowData: [String: ListJSONValue]

    public init(rowData: [String: ListJSONValue]) {
        self.rowData = rowData
    }
}

/// `PATCH /api/lists/[id]/data/[rowId]` body: partial `{ "rowData": { ... } }`.
public struct UpdateListRowRequest: Codable, Sendable, Equatable {
    public let rowData: [String: ListJSONValue]

    public init(rowData: [String: ListJSONValue]) {
        self.rowData = rowData
    }
}

/// `PUT /api/lists/[id]/watchers/[userId]` body: `{ "role": "<role>" }`.
public struct UpdateListWatcherRequest: Codable, Sendable, Equatable {
    public let role: String

    public init(role: String) {
        self.role = role
    }
}

/// `POST /api/lists/connections` body.
public struct CreateListConnectionRequest: Codable, Sendable, Equatable {
    public let fromListId: String
    public let toListId: String
    public let label: String?

    public init(fromListId: String, toListId: String, label: String? = nil) {
        self.fromListId = fromListId
        self.toListId = toListId
        self.label = label
    }
}
