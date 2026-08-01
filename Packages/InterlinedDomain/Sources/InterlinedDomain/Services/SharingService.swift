import Foundation
import InterlinedKit

// MARK: - SharingError

public enum SharingError: Error, Sendable, Equatable {
    /// Creating a share link requires an active subscription (free tier gets a
    /// 403 server-side). Raised before any HTTP call.
    case subscriberRequired
}

extension SharingError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case .subscriberRequired: return "Creating share links requires an active subscription."
        }
    }
}

// MARK: - SharingServicing

/// The sharing surface the App layer codes against (the-gaps.md G3) — create,
/// list, and revoke tokenized share links for lists and documents, and
/// resolve/claim a link from a pasted URL or `interlinedlist://` deep link.
///
/// Creating a link is subscriber-gated (mirrors `ListsService`'s entitlement
/// seam); resolving/claiming/revoking are not, so downgraded owners can still
/// revoke and any recipient can claim.
public protocol SharingServicing: Sendable {
    // Lists
    func listShareLinks(listId: String) async throws -> [ShareLink]
    func createListShareLink(listId: String, role: ShareRole, expiresAt: Date?) async throws -> ShareLink
    func revokeListShareLink(listId: String, token: String) async throws -> Bool
    func resolveListShare(token: String) async throws -> ResolvedShare
    func claimListShare(token: String) async throws -> ShareClaim

    // Documents
    func documentShareLinks(documentId: String) async throws -> [ShareLink]
    func createDocumentShareLink(documentId: String, role: ShareRole, expiresAt: Date?) async throws -> ShareLink
    func revokeDocumentShareLink(documentId: String, token: String) async throws -> Bool
    func resolveDocumentShare(token: String) async throws -> ResolvedShare
    func claimDocumentShare(token: String) async throws -> ShareClaim
}

public extension SharingServicing {
    func createListShareLink(listId: String, role: ShareRole = .watcher) async throws -> ShareLink {
        try await createListShareLink(listId: listId, role: role, expiresAt: nil)
    }
    func createDocumentShareLink(documentId: String, role: ShareRole = .watcher) async throws -> ShareLink {
        try await createDocumentShareLink(documentId: documentId, role: role, expiresAt: nil)
    }
}

// MARK: - SharingService

public final class SharingService: SharingServicing {

    private let api: APIClientProtocol
    private let entitlements: EntitlementsService

    public init(
        api: APIClientProtocol,
        entitlements: EntitlementsService = EntitlementsService(customerStatus: .free)
    ) {
        self.api = api
        self.entitlements = entitlements
    }

    // MARK: Lists

    public func listShareLinks(listId: String) async throws -> [ShareLink] {
        let dto = try await api.send(Sharing.listShareLinks(listId: listId))
        return dto.shareLinks.map(ShareLink.init(from:))
    }

    public func createListShareLink(listId: String, role: ShareRole, expiresAt: Date?) async throws -> ShareLink {
        guard entitlements.isSubscriber else { throw SharingError.subscriberRequired }
        let dto = try await api.send(
            Sharing.createListShareLink(listId: listId, CreateShareLinkRequest(role: role.rawValue, expiresAt: expiresAt))
        )
        return ShareLink(from: dto)
    }

    public func revokeListShareLink(listId: String, token: String) async throws -> Bool {
        let dto = try await api.send(Sharing.revokeListShareLink(listId: listId, token: token))
        return dto.revoked ?? true
    }

    public func resolveListShare(token: String) async throws -> ResolvedShare {
        ResolvedShare(from: try await api.send(Sharing.resolveListShare(token: token)))
    }

    public func claimListShare(token: String) async throws -> ShareClaim {
        let dto = try await api.send(Sharing.claimListShare(token: token))
        return ShareClaim(resourceId: dto.listId, role: dto.role.flatMap(ShareRole.init(rawValue:)))
    }

    // MARK: Documents

    public func documentShareLinks(documentId: String) async throws -> [ShareLink] {
        let dto = try await api.send(Sharing.documentShareLinks(documentId: documentId))
        return dto.shareLinks.map(ShareLink.init(from:))
    }

    public func createDocumentShareLink(documentId: String, role: ShareRole, expiresAt: Date?) async throws -> ShareLink {
        guard entitlements.isSubscriber else { throw SharingError.subscriberRequired }
        let dto = try await api.send(
            Sharing.createDocumentShareLink(documentId: documentId, CreateShareLinkRequest(role: role.rawValue, expiresAt: expiresAt))
        )
        return ShareLink(from: dto)
    }

    public func revokeDocumentShareLink(documentId: String, token: String) async throws -> Bool {
        let dto = try await api.send(Sharing.revokeDocumentShareLink(documentId: documentId, token: token))
        return dto.revoked ?? true
    }

    public func resolveDocumentShare(token: String) async throws -> ResolvedShare {
        ResolvedShare(from: try await api.send(Sharing.resolveDocumentShare(token: token)))
    }

    public func claimDocumentShare(token: String) async throws -> ShareClaim {
        let dto = try await api.send(Sharing.claimDocumentShare(token: token))
        return ShareClaim(resourceId: dto.documentId, role: dto.role.flatMap(ShareRole.init(rawValue:)))
    }
}
