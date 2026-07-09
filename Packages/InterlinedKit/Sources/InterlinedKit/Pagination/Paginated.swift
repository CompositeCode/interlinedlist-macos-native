import Foundation

// MARK: - PaginationInfo

/// The `pagination` envelope every list endpoint returns:
/// `{ total, limit, offset, hasMore }`.
public struct PaginationInfo: Decodable, Sendable, Equatable {
    public let total: Int
    public let limit: Int
    public let offset: Int
    public let hasMore: Bool

    public init(total: Int, limit: Int, offset: Int, hasMore: Bool) {
        self.total = total
        self.limit = limit
        self.offset = offset
        self.hasMore = hasMore
    }
}

// MARK: - Paginated<T>

/// Generic envelope for list responses of the shape:
///
/// ```json
/// { "<collectionKey>": [...], "pagination": { ... } }
/// ```
///
/// where `<collectionKey>` varies per endpoint (`"messages"`, `"lists"`,
/// `"organizations"`, …). The collection key is supplied at decode time by
/// the endpoint builder via the request's `paginationKey` and the dedicated
/// initializer below, so a single `Paginated<T>` type covers every list.
public struct Paginated<Item: Decodable & Sendable>: Sendable {
    public let items: [Item]
    public let pagination: PaginationInfo

    public init(items: [Item], pagination: PaginationInfo) {
        self.items = items
        self.pagination = pagination
    }
}

// MARK: - PaginatedDecoder

/// Decodes a `Paginated<T>` from JSON given a runtime-known `collectionKey`.
///
/// `Paginated<T>` itself does not conform to `Decodable` because the JSON
/// key for the collection varies per endpoint. The decoder is invoked by
/// `APIClient` after it learns the key from `Request.paginationKey`. (Endpoint
/// builders that want simpler call sites can also build a wrapper DTO that
/// conforms to `Decodable` directly — both patterns are supported.)
public enum PaginatedDecoder {
    /// Decodes a full `Paginated<T>` — requires both the collection array and
    /// a `"pagination"` envelope in the response JSON. Use this for endpoints
    /// (e.g. Messages) whose responses always include pagination metadata.
    public static func decode<Item: Decodable & Sendable>(
        _ itemType: Item.Type,
        collectionKey: String,
        from data: Data,
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) throws -> Paginated<Item> {
        let container = try decoder.decode([String: JSONValue].self, from: data)

        guard let rawItems = container[collectionKey] else {
            throw APIError.decoding(
                type: "Paginated<\(itemType)>",
                message: "Missing collection key \"\(collectionKey)\""
            )
        }
        guard let rawPagination = container["pagination"] else {
            throw APIError.decoding(
                type: "Paginated<\(itemType)>",
                message: "Missing \"pagination\" envelope"
            )
        }

        let itemsData = try JSONEncoder().encode(rawItems)
        let paginationData = try JSONEncoder().encode(rawPagination)

        let items = try decoder.decode([Item].self, from: itemsData)
        let pagination = try decoder.decode(PaginationInfo.self, from: paginationData)
        return Paginated(items: items, pagination: pagination)
    }

    /// Decodes just the items array from a JSON envelope keyed by
    /// `collectionKey`. Unlike `decode(_:collectionKey:from:decoder:)`, this
    /// does NOT require a `"pagination"` envelope — use it for endpoints whose
    /// list responses omit pagination metadata (e.g. Documents, Folders).
    public static func decodeItems<Item: Decodable & Sendable>(
        _ itemType: Item.Type,
        collectionKey: String,
        from data: Data,
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) throws -> [Item] {
        let container = try decoder.decode([String: JSONValue].self, from: data)
        guard let rawItems = container[collectionKey] else {
            throw APIError.decoding(
                type: "[\(itemType)]",
                message: "Missing collection key \"\(collectionKey)\""
            )
        }
        let itemsData = try JSONEncoder().encode(rawItems)
        return try decoder.decode([Item].self, from: itemsData)
    }
}

// MARK: - JSONValue (private intermediate)

/// A minimal type-erased JSON value used by `PaginatedDecoder` to split a
/// response into its collection + pagination halves without re-decoding the
/// whole body twice. Kept private to the kit.
enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
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
