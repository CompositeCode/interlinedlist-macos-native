import Foundation
import InterlinedKit

// MARK: - DirectMessagesError

public enum DirectMessagesError: Error, Sendable, Equatable {
    /// Attempted to send a message with no text and no images.
    case emptyMessage
}

extension DirectMessagesError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case .emptyMessage: return "A message needs text or an image before it can be sent."
        }
    }
}

// MARK: - DirectMessagesServicing

/// The Direct Messages surface the App layer codes against (work-consolidation.md G1) —
/// list folders, load and poll a thread, send, discover eligible recipients,
/// the unread badge count, and per-side read/trash/restore.
///
/// Free tier — no subscriber gate. Eligibility (mutual-follow, not-blocked) is
/// enforced by the server; the service surfaces the server's error. `send`
/// rejects an empty message client-side before any request. Read/trash/restore
/// are fire-and-forget (`sendVoid`).
public protocol DirectMessagesServicing: Sendable {
    func folder(_ folder: DMFolder, cursor: String?) async throws -> DMPage
    func thread(username: String, cursor: String?) async throws -> DMThread
    func threadUpdates(username: String, since: String?) async throws -> DMThread
    func send(recipientId: String, body: String, imageURLs: [String]) async throws -> DirectMessage
    func recipients() async throws -> [UserSummary]
    func unreadCount() async throws -> Int
    func markRead(id: String) async throws
    func trash(id: String) async throws
    func restore(id: String) async throws
}

public extension DirectMessagesServicing {
    func folder(_ folder: DMFolder = .inbox) async throws -> DMPage {
        try await self.folder(folder, cursor: nil)
    }
    func thread(username: String) async throws -> DMThread {
        try await thread(username: username, cursor: nil)
    }
    func send(recipientId: String, body: String) async throws -> DirectMessage {
        try await send(recipientId: recipientId, body: body, imageURLs: [])
    }
}

// MARK: - DirectMessagesService

public final class DirectMessagesService: DirectMessagesServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func folder(_ folder: DMFolder, cursor: String?) async throws -> DMPage {
        let dto = try await api.send(DirectMessages.folder(folder.rawValue, cursor: cursor))
        return DMPage(from: dto)
    }

    public func thread(username: String, cursor: String?) async throws -> DMThread {
        let dto = try await api.send(DirectMessages.thread(username: username, cursor: cursor))
        return DMThread(from: dto)
    }

    public func threadUpdates(username: String, since: String?) async throws -> DMThread {
        let dto = try await api.send(DirectMessages.threadUpdates(username: username, since: since))
        return DMThread(from: dto)
    }

    public func send(recipientId: String, body: String, imageURLs: [String]) async throws -> DirectMessage {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageURLs.isEmpty else { throw DirectMessagesError.emptyMessage }
        let request = SendDirectMessageRequest(
            recipientId: recipientId,
            body: trimmed,
            imageUrls: imageURLs.isEmpty ? nil : imageURLs
        )
        let response = try await api.send(DirectMessages.send(request))
        return DirectMessage(from: response.message)
    }

    public func recipients() async throws -> [UserSummary] {
        let dto = try await api.send(DirectMessages.recipients())
        return dto.recipients.map(UserSummary.init(from:))
    }

    public func unreadCount() async throws -> Int {
        try await api.send(DirectMessages.unreadCount()).count
    }

    public func markRead(id: String) async throws {
        try await api.sendVoid(DirectMessages.markRead(id: id))
    }

    public func trash(id: String) async throws {
        try await api.sendVoid(DirectMessages.trash(id: id))
    }

    public func restore(id: String) async throws {
        try await api.sendVoid(DirectMessages.restore(id: id))
    }
}
