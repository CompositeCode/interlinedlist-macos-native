import Foundation
import InterlinedKit

// MARK: - DirectMessagesError

public enum DirectMessagesError: Error, Sendable, Equatable {
    /// Attempted to send a message with no text and no images.
    case emptyMessage

    /// More photos were queued than the documented per-message cap
    /// (work-consolidation.md G22). Rejected client-side before any upload, so
    /// we never burn a round-trip on bytes the server will refuse.
    case tooManyImages(limit: Int)

    /// The body exceeded the documented DM character ceiling. Note this is
    /// 10,000 for DMs — far larger than the 5,000 the *post* composer enforces
    /// from `GET /api/limits`; the two surfaces are not the same limit.
    case bodyTooLong(limit: Int)
}

extension DirectMessagesError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case .emptyMessage:
            return "A message needs text or an image before it can be sent."
        case .tooManyImages(let limit):
            return "You can attach up to \(limit) photos to a direct message."
        case .bodyTooLong(let limit):
            return "A direct message can be up to \(limit) characters."
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

    /// The server-grouped inbox (work-consolidation.md G22). One row per
    /// conversation, keyed by `pairKey`, newest first, with its own cursor.
    ///
    /// This supersedes collapsing `folder(.inbox)` client-side for the inbox.
    /// The folder listing is still the right call for Sent and Deleted, which
    /// this route does not replace.
    func conversations(cursor: String?) async throws -> DMConversationPage

    /// One message by id — the deep-link target (work-consolidation.md G22).
    func message(id: String) async throws -> DirectMessage

    /// Prepares and uploads one photo, returning its hosted URL for
    /// `send(recipientId:body:imageURLs:)` (work-consolidation.md G22).
    ///
    /// Sending photos requires a **verified email address**. This method does
    /// NOT pre-check that: the server's 403 is surfaced verbatim instead.
    /// TODO(#41): the email-verification gate is owned by issue #41, which
    /// builds `CapabilityGate` (status → email verification → tier). When that
    /// branch merges, have the DM composers ask the gate so the affordance is
    /// explained *before* the user picks a file. Do not add a second check
    /// here — one gate, one owner.
    func uploadImage(_ data: Data) async throws -> String

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
    func conversations() async throws -> DMConversationPage {
        try await conversations(cursor: nil)
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

    /// Source of the server-authoritative image size ceilings (G14). Optional
    /// so hosts that do not wire it fall back to `ContentLimits.default` — the
    /// same values `ImagePrep` bakes in — rather than failing to upload.
    private let contentLimits: ContentLimitsProviding?

    public init(api: APIClientProtocol, contentLimits: ContentLimitsProviding? = nil) {
        self.api = api
        self.contentLimits = contentLimits
    }

    public func folder(_ folder: DMFolder, cursor: String?) async throws -> DMPage {
        let dto = try await api.send(DirectMessages.folder(folder.rawValue, cursor: cursor))
        return DMPage(from: dto)
    }

    public func conversations(cursor: String?) async throws -> DMConversationPage {
        let dto = try await api.send(DirectMessages.conversations(cursor: cursor))
        return DMConversationPage(from: dto)
    }

    public func message(id: String) async throws -> DirectMessage {
        let dto = try await api.send(DirectMessages.message(id: id))
        return DirectMessage(from: dto.message)
    }

    public func uploadImage(_ data: Data) async throws -> String {
        // Prefer the live `GET /api/limits` ceilings (G14 tail) so the prep
        // budget is server-driven; `ContentLimits.default` when no provider is
        // injected or the fetch failed. Identical to the post composer's path —
        // deliberately the same `ImagePrep` pipeline, not fresh constants.
        let limits = await contentLimits?.limits() ?? .default
        let prepared = try ImagePrep.prepare(data, limits: limits.imagePrepLimits)
        // A 403 here is the documented "verified email required" refusal. It
        // propagates untouched: `APIError.forbidden` preserves the server's own
        // wording, which is the canonical explanation for the user.
        // TODO(#41): the email-verification gate is owned by issue #41 and
        // arrives as `CapabilityGate`. When it lands, the composer should
        // disable the attach affordance up front and explain why. Do not add a
        // competing pre-check in this service.
        let response = try await api.send(
            DirectMessages.uploadImage(prepared.data, contentType: prepared.format.mimeType)
        )
        return response.url
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
        // The documented DM ceilings (G22). Rejected before the request so a
        // doomed payload never leaves the machine.
        guard imageURLs.count <= DMLimits.maxImagesPerMessage else {
            throw DirectMessagesError.tooManyImages(limit: DMLimits.maxImagesPerMessage)
        }
        guard trimmed.count <= DMLimits.maxBodyCharacters else {
            throw DirectMessagesError.bodyTooLong(limit: DMLimits.maxBodyCharacters)
        }
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
