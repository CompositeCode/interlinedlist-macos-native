import Foundation

// MARK: - Moderation DTOs (the-gaps.md G2)
//
// Block / mute / report. Envelope keys verified live 2026-07-31 (authenticated
// Bearer probe): `GET /api/user/blocks` → `{ blockedUsers: [...], pagination }`,
// `GET /api/user/mutes` → `{ mutedUsers: [...], pagination }`. The list rows
// were empty in the probe, so fields beyond `id` are modelled optional — they
// follow the standard compact-user shape `{ id, username, displayName, avatar }`.

/// A user as surfaced by the block/mute list endpoints.
public struct ModeratedUserDTO: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let avatar: String?

    public init(id: String, username: String? = nil, displayName: String? = nil, avatar: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
    }
}

/// `GET /api/user/blocks` — `{ blockedUsers: [...], pagination: {...} }`.
public struct BlockedUsersResponse: Decodable, Sendable, Equatable {
    public let blockedUsers: [ModeratedUserDTO]
    public let pagination: PaginationInfo?

    public init(blockedUsers: [ModeratedUserDTO], pagination: PaginationInfo? = nil) {
        self.blockedUsers = blockedUsers
        self.pagination = pagination
    }
}

/// `GET /api/user/mutes` — `{ mutedUsers: [...], pagination: {...} }`.
public struct MutedUsersResponse: Decodable, Sendable, Equatable {
    public let mutedUsers: [ModeratedUserDTO]
    public let pagination: PaginationInfo?

    public init(mutedUsers: [ModeratedUserDTO], pagination: PaginationInfo? = nil) {
        self.mutedUsers = mutedUsers
        self.pagination = pagination
    }
}

/// Request body for `POST /api/users/{username}/report` and
/// `POST /api/messages/{id}/report`: `{ reason, detail? }`. `reason` is one of
/// `harassment|spam|misinformation|inappropriate|other` (validated in the
/// domain layer via the `ReportReason` enum).
public struct ReportRequest: Encodable, Sendable, Equatable {
    public let reason: String
    public let detail: String?

    public init(reason: String, detail: String? = nil) {
        self.reason = reason
        self.detail = detail
    }
}

/// A decode-safe acknowledgement for the moderation write actions. Every field
/// is optional so it decodes regardless of the exact success body the server
/// returns (`{}`, `{ ok: true }`, `{ blocked: true }`, …). The service sends
/// these via `sendVoid`, so the body is ignored; this type exists only to give
/// the builders a concrete `Request<Response>` return type.
public struct ModerationAck: Decodable, Sendable, Equatable {
    public let ok: Bool?

    public init(ok: Bool? = nil) {
        self.ok = ok
    }
}
