import Foundation

/// `GET /api/user/sessions` response — the account's active sessions
/// (work-consolidation.md G19). Shape recorded in the gap definition:
///
/// ```json
/// { "sessions": [ { "id": "sess_1", "deviceLabel": "MacBook Pro",
///                   "createdAt": "2026-09-01T10:00:00Z",
///                   "lastUsedAt": "2026-09-05T18:22:00Z",
///                   "isCurrent": true } ] }
/// ```
///
/// Decodes the named envelope **or** a bare array, matching the tolerance the
/// GitHub DTOs adopted after the live API was found to wrap some collections
/// and not others. Every field but `id` is optional so an added, renamed, or
/// dropped field never fails the whole decode.
public struct SessionsResponse: Decodable, Sendable, Equatable {
    public let sessions: [SessionDTO]

    public init(sessions: [SessionDTO]) {
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        // Bare array first: `[ {...}, {...} ]`.
        if let single = try? decoder.singleValueContainer(),
           let bare = try? single.decode([SessionDTO].self) {
            self.sessions = bare
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessions = try container.decodeIfPresent([SessionDTO].self, forKey: .sessions) ?? []
    }

    private enum CodingKeys: String, CodingKey { case sessions }
}

/// One active session / issued token.
public struct SessionDTO: Decodable, Sendable, Equatable {
    public let id: String
    public let deviceLabel: String?
    public let createdAt: Date?
    public let lastUsedAt: Date?
    public let isCurrent: Bool?

    public init(
        id: String,
        deviceLabel: String? = nil,
        createdAt: Date? = nil,
        lastUsedAt: Date? = nil,
        isCurrent: Bool? = nil
    ) {
        self.id = id
        self.deviceLabel = deviceLabel
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isCurrent = isCurrent
    }
}
