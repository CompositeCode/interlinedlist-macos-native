import Foundation
import InterlinedKit

/// One active sign-in / issued token on the account (work-consolidation.md G19).
///
/// Drives Settings ▸ Security, where each row can be revoked. `isCurrent`
/// marks the session this app is running on — the UI must not offer to revoke
/// it without warning, since doing so signs the user out.
public struct ActiveSession: Sendable, Equatable, Identifiable {
    public let id: String
    /// Human label for the machine, e.g. "MacBook Pro". Falls back to a generic
    /// string when the server omits it, so a row always has something to show.
    public let deviceLabel: String
    public let createdAt: Date?
    public let lastUsedAt: Date?
    /// Whether this row is the session the app is currently using.
    public let isCurrent: Bool

    public init(
        id: String,
        deviceLabel: String,
        createdAt: Date? = nil,
        lastUsedAt: Date? = nil,
        isCurrent: Bool = false
    ) {
        self.id = id
        self.deviceLabel = deviceLabel
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isCurrent = isCurrent
    }
}

extension ActiveSession {
    /// Maps the DTO. A missing label collapses to "Unknown device" and a missing
    /// `isCurrent` to `false` — the safe default, since it only ever *enables*
    /// the revoke affordance.
    public init(from dto: SessionDTO) {
        self.init(
            id: dto.id,
            deviceLabel: dto.deviceLabel ?? "Unknown device",
            createdAt: dto.createdAt,
            lastUsedAt: dto.lastUsedAt,
            isCurrent: dto.isCurrent ?? false
        )
    }
}
