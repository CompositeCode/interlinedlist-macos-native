import Foundation

// MARK: - NotificationDTO

/// A single notification (`items[]` from `GET /api/notifications`).
///
/// `metadata` is a flexible map because its contents vary by notification
/// `type` (dig, reply, follow, …). Optional fields mirror the API reference:
/// `actionUrl`, `type`, and `readAt` are not always present.
public struct NotificationDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let body: String?
    public let actionUrl: String?
    public let type: String?
    public let metadata: [String: NotificationMetadataValue]?
    public let createdAt: Date?
    public let readAt: Date?

    public init(
        id: String,
        title: String? = nil,
        body: String? = nil,
        actionUrl: String? = nil,
        type: String? = nil,
        metadata: [String: NotificationMetadataValue]? = nil,
        createdAt: Date? = nil,
        readAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.actionUrl = actionUrl
        self.type = type
        self.metadata = metadata
        self.createdAt = createdAt
        self.readAt = readAt
    }
}

// MARK: - NotificationMetadataValue

/// Flexible, type-erased value for the notification `metadata` map, whose
/// shape depends on the notification type. Group-prefixed to avoid clashing
/// with other JSON-map helpers in the kit.
public enum NotificationMetadataValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([NotificationMetadataValue])
    case object([String: NotificationMetadataValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([NotificationMetadataValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: NotificationMetadataValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value in notification metadata"
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

// MARK: - NotificationTrayDTO

/// `GET /api/notifications` (with `scope=tray`) response:
/// `{ "unreadCount": Int, "items": [NotificationDTO] }`.
public struct NotificationTrayDTO: Codable, Sendable, Equatable {
    public let unreadCount: Int
    public let items: [NotificationDTO]

    public init(unreadCount: Int, items: [NotificationDTO]) {
        self.unreadCount = unreadCount
        self.items = items
    }
}

// MARK: - Action responses

/// `PATCH /api/notifications/[id]/read` response: `{ "ok": true }`.
public struct NotificationReadResponse: Codable, Sendable, Equatable {
    public let ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

/// `POST /api/notifications/mark-all-read` response:
/// `{ "ok": true, "updated": Int }`.
public struct NotificationMarkAllReadResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let updated: Int

    public init(ok: Bool, updated: Int) {
        self.ok = ok
        self.updated = updated
    }
}
