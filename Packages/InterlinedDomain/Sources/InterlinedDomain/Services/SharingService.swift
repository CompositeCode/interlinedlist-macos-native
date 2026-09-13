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

/// The sharing surface the App layer codes against (work-consolidation.md G3) — create,
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

    /// Reads one page of a token-shared list's rows
    /// (`GET /api/lists/shared/{token}/data`, work-consolidation.md G23).
    ///
    /// The **token is the capability**: rows are served with no session and
    /// regardless of the list's `isPublic` flag, which is what lets a
    /// read-only share render a private list. Pairs with
    /// `resolveListShare(token:)` — resolve gives the title and role, this
    /// gives the rows.
    func sharedListRows(token: String, limit: Int, offset: Int) async throws -> RowsPage

    /// Resolves an email invite for its landing page
    /// (`GET /api/lists/invite/{token}`, work-consolidation.md G23).
    ///
    /// There is deliberately no `claimListInvite`: the accept half
    /// (`POST /api/lists/invite/{token}`) is session-only in the live spec, so
    /// a Bearer client cannot reach it. The landing hands accept to the browser.
    func resolveListInvite(token: String) async throws -> ResolvedListInvite

    // Documents
    func documentShareLinks(documentId: String) async throws -> [ShareLink]
    func createDocumentShareLink(documentId: String, role: ShareRole, expiresAt: Date?) async throws -> ShareLink
    func revokeDocumentShareLink(documentId: String, token: String) async throws -> Bool
    func resolveDocumentShare(token: String) async throws -> ResolvedShare
    func claimDocumentShare(token: String) async throws -> ShareClaim

    // Document collaborators (per-person access)
    func documentCollaborators(documentId: String) async throws -> [Collaborator]
    func searchDocumentCollaborators(documentId: String, query: String) async throws -> [CollaboratorCandidate]
    func addDocumentCollaborator(documentId: String, userId: String, role: ShareRole, notify: Bool) async throws
    func setDocumentCollaboratorRole(documentId: String, userId: String, role: ShareRole, notify: Bool) async throws
    func removeDocumentCollaborator(documentId: String, userId: String) async throws -> Bool

    // Email invites (documents + lists)
    func documentInvites(documentId: String) async throws -> [ShareInvite]
    func createDocumentInvite(documentId: String, email: String, role: ShareRole, expiresAt: Date?) async throws -> SentInvite
    func revokeDocumentInvite(documentId: String, token: String) async throws -> Bool
    func listInvites(listId: String) async throws -> [ShareInvite]
    func createListInvite(listId: String, email: String, role: ShareRole, expiresAt: Date?) async throws -> SentInvite
    func revokeListInvite(listId: String, token: String) async throws -> Bool
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
    private let decoder: JSONDecoder

    public init(
        api: APIClientProtocol,
        entitlements: EntitlementsService = EntitlementsService(customerStatus: .free),
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) {
        self.api = api
        self.entitlements = entitlements
        self.decoder = decoder
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

    public func sharedListRows(token: String, limit: Int, offset: Int) async throws -> RowsPage {
        // Ungated on both axes: no entitlement check (reading a share you were
        // given is always free) and no auth (`Lists.sharedRows` is `.none`).
        let request = Lists.sharedRows(token: token, limit: limit, offset: offset)
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "data"
        let paginated = try PaginatedDecoder.decode(
            ListRowDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        return RowsPage(from: paginated)
    }

    public func resolveListInvite(token: String) async throws -> ResolvedListInvite {
        // Accepting an invite is documented as always free, so no entitlement
        // gate belongs on the landing read either.
        ResolvedListInvite(from: try await api.send(Lists.invite(token: token)))
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

    // MARK: Document collaborators

    public func documentCollaborators(documentId: String) async throws -> [Collaborator] {
        let dto = try await api.send(Sharing.documentCollaborators(documentId: documentId))
        return dto.collaborators.map(Collaborator.init(from:))
    }

    public func searchDocumentCollaborators(documentId: String, query: String) async throws -> [CollaboratorCandidate] {
        let dto = try await api.send(Sharing.searchDocumentCollaborators(documentId: documentId, query: query))
        return dto.users.map(CollaboratorCandidate.init(from:))
    }

    public func addDocumentCollaborator(documentId: String, userId: String, role: ShareRole, notify: Bool) async throws {
        guard entitlements.isSubscriber else { throw SharingError.subscriberRequired }
        _ = try await api.send(
            Sharing.addDocumentCollaborator(documentId: documentId, AddCollaboratorRequest(userId: userId, role: role.rawValue, notify: notify))
        )
    }

    public func setDocumentCollaboratorRole(documentId: String, userId: String, role: ShareRole, notify: Bool) async throws {
        guard entitlements.isSubscriber else { throw SharingError.subscriberRequired }
        _ = try await api.send(
            Sharing.setDocumentCollaboratorRole(documentId: documentId, userId: userId, SetCollaboratorRoleRequest(role: role.rawValue, notify: notify))
        )
    }

    public func removeDocumentCollaborator(documentId: String, userId: String) async throws -> Bool {
        let dto = try await api.send(Sharing.removeDocumentCollaborator(documentId: documentId, userId: userId))
        return dto.removed ?? true
    }

    // MARK: Email invites (documents + lists)

    public func documentInvites(documentId: String) async throws -> [ShareInvite] {
        let dto = try await api.send(Sharing.documentInvites(documentId: documentId))
        return dto.invites.map(ShareInvite.init(from:))
    }

    public func createDocumentInvite(documentId: String, email: String, role: ShareRole, expiresAt: Date?) async throws -> SentInvite {
        guard entitlements.isSubscriber else { throw SharingError.subscriberRequired }
        let dto = try await api.send(
            Sharing.createDocumentInvite(documentId: documentId, CreateInviteRequest(email: email, role: role.rawValue, expiresAt: expiresAt))
        )
        return SentInvite(from: dto)
    }

    public func revokeDocumentInvite(documentId: String, token: String) async throws -> Bool {
        let dto = try await api.send(Sharing.revokeDocumentInvite(documentId: documentId, token: token))
        return dto.revoked ?? true
    }

    public func listInvites(listId: String) async throws -> [ShareInvite] {
        let dto = try await api.send(Sharing.listInvites(listId: listId))
        return dto.invites.map(ShareInvite.init(from:))
    }

    public func createListInvite(listId: String, email: String, role: ShareRole, expiresAt: Date?) async throws -> SentInvite {
        guard entitlements.isSubscriber else { throw SharingError.subscriberRequired }
        let dto = try await api.send(
            Sharing.createListInvite(listId: listId, CreateInviteRequest(email: email, role: role.rawValue, expiresAt: expiresAt))
        )
        return SentInvite(from: dto)
    }

    public func revokeListInvite(listId: String, token: String) async throws -> Bool {
        let dto = try await api.send(Sharing.revokeListInvite(listId: listId, token: token))
        return dto.revoked ?? true
    }
}
