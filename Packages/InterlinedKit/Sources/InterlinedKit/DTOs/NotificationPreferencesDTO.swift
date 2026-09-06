import Foundation

/// `GET /api/user/notification-preferences` response (work-consolidation.md G18)
/// — a **server-driven event catalogue**, so the pane renders itself from the
/// payload rather than hard-coding a list of switches:
///
/// ```json
/// { "events": [ { "key": "dig",
///                 "label": "Digs on your messages",
///                 "description": "…",
///                 "channels": { "push": true, "inApp": true } } ] }
/// ```
///
/// Only `key` is required — an event whose label the server has not filled in
/// still renders (the domain mapper falls back to the key), and an unknown
/// channel never breaks the decode.
public struct NotificationPreferencesResponse: Decodable, Sendable, Equatable {
    public let events: [NotificationEventDTO]

    public init(events: [NotificationEventDTO]) { self.events = events }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let bare = try? single.decode([NotificationEventDTO].self) {
            self.events = bare
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.events = try c.decodeIfPresent([NotificationEventDTO].self, forKey: .events) ?? []
    }

    private enum CodingKeys: String, CodingKey { case events }
}

/// One notification event in the catalogue, with its per-channel toggles.
public struct NotificationEventDTO: Decodable, Sendable, Equatable {
    public let key: String
    public let label: String?
    public let description: String?
    public let channels: NotificationChannelsDTO?

    public init(
        key: String,
        label: String? = nil,
        description: String? = nil,
        channels: NotificationChannelsDTO? = nil
    ) {
        self.key = key
        self.label = label
        self.description = description
        self.channels = channels
    }
}

/// The per-event delivery channels. `push` is the switchboard G9 (APNs) will
/// read once push ships.
public struct NotificationChannelsDTO: Codable, Sendable, Equatable {
    public let push: Bool?
    public let inApp: Bool?
    public let email: Bool?

    public init(push: Bool? = nil, inApp: Bool? = nil, email: Bool? = nil) {
        self.push = push
        self.inApp = inApp
        self.email = email
    }
}

// MARK: - Write

/// `PATCH /api/user/notification-preferences` request body.
///
/// The gap definition records that `PATCH` writes the catalogue but does not
/// pin the request shape. This mirrors the read envelope with only the fields a
/// write needs — the event `key` and its `channels` — which is the shape the
/// rest of this API uses for partial updates (send what changed, omit the
/// server-owned display fields). Labels and descriptions are server-owned and
/// deliberately not echoed back.
public struct UpdateNotificationPreferencesRequest: Encodable, Sendable, Equatable {
    public let events: [EventUpdate]

    public init(events: [EventUpdate]) { self.events = events }

    public struct EventUpdate: Encodable, Sendable, Equatable {
        public let key: String
        public let channels: NotificationChannelsDTO

        public init(key: String, channels: NotificationChannelsDTO) {
            self.key = key
            self.channels = channels
        }
    }
}
