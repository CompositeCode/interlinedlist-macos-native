import Foundation
import InterlinedKit

// MARK: - ModerationServicing

/// The moderation surface the App layer codes against (the-gaps.md G2) — list
/// the accounts you block / mute, block / unblock, mute / unmute, and report
/// users or messages.
///
/// Follows the domain-service DI shape: takes its `APIClientProtocol` so unit
/// tests run against a stub. The write actions are fire-and-forget (sent via
/// `sendVoid`); success is a non-throwing 2xx. `isBlocking(username:)` is
/// computed from the blocks list so it needs no unverified per-user status
/// endpoint.
public protocol ModerationServicing: Sendable {
    func blockedUsers(limit: Int, offset: Int) async throws -> [ModeratedUser]
    func mutedUsers(limit: Int, offset: Int) async throws -> [ModeratedUser]

    func block(username: String) async throws
    func unblock(username: String) async throws
    func mute(username: String) async throws
    func unmute(username: String) async throws

    func reportUser(username: String, reason: ReportReason, detail: String?) async throws
    func reportMessage(id: String, reason: ReportReason, detail: String?) async throws

    /// Whether the current account blocks `username`, computed by scanning the
    /// blocks list (case-insensitive on username, or an id match).
    func isBlocking(username: String) async throws -> Bool
}

public extension ModerationServicing {
    /// Convenience overloads with the default page size (50).
    func blockedUsers() async throws -> [ModeratedUser] {
        try await blockedUsers(limit: 50, offset: 0)
    }
    func mutedUsers() async throws -> [ModeratedUser] {
        try await mutedUsers(limit: 50, offset: 0)
    }
    func reportUser(username: String, reason: ReportReason) async throws {
        try await reportUser(username: username, reason: reason, detail: nil)
    }
    func reportMessage(id: String, reason: ReportReason) async throws {
        try await reportMessage(id: id, reason: reason, detail: nil)
    }
}

// MARK: - ModerationService

public final class ModerationService: ModerationServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    // MARK: Lists

    public func blockedUsers(limit: Int, offset: Int) async throws -> [ModeratedUser] {
        let dto = try await api.send(Moderation.blocks(limit: limit, offset: offset))
        return dto.blockedUsers.map(ModeratedUser.init(from:))
    }

    public func mutedUsers(limit: Int, offset: Int) async throws -> [ModeratedUser] {
        let dto = try await api.send(Moderation.mutes(limit: limit, offset: offset))
        return dto.mutedUsers.map(ModeratedUser.init(from:))
    }

    // MARK: Block / mute actions (fire-and-forget)

    public func block(username: String) async throws {
        try await api.sendVoid(Moderation.block(username: username))
    }

    public func unblock(username: String) async throws {
        try await api.sendVoid(Moderation.unblock(username: username))
    }

    public func mute(username: String) async throws {
        try await api.sendVoid(Moderation.mute(username: username))
    }

    public func unmute(username: String) async throws {
        try await api.sendVoid(Moderation.unmute(username: username))
    }

    // MARK: Reporting

    public func reportUser(username: String, reason: ReportReason, detail: String?) async throws {
        try await api.sendVoid(
            Moderation.reportUser(username: username, reason: reason.rawValue, detail: Self.normalize(detail))
        )
    }

    public func reportMessage(id: String, reason: ReportReason, detail: String?) async throws {
        try await api.sendVoid(
            Moderation.reportMessage(id: id, reason: reason.rawValue, detail: Self.normalize(detail))
        )
    }

    // MARK: Derived state

    public func isBlocking(username: String) async throws -> Bool {
        let blocked = try await blockedUsers(limit: 100, offset: 0)
        return blocked.contains { user in
            user.id == username
                || user.username?.caseInsensitiveCompare(username) == .orderedSame
        }
    }

    // MARK: - Helpers

    /// Trims free-text detail and collapses an empty string to `nil` so the
    /// request omits the field rather than sending `""`.
    private static func normalize(_ detail: String?) -> String? {
        guard let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
