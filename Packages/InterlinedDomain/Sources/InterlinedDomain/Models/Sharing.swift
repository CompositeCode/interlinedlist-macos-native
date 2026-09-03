import Foundation
import InterlinedKit

// MARK: - ShareRole

/// A share grant's capability level (work-consolidation.md G3). Values match the live API
/// (`watcher|collaborator|manager`); the UI labels follow the docs
/// (Viewer/Editor/Admin).
public enum ShareRole: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case watcher
    case collaborator
    case manager

    public var id: String { rawValue }

    /// UI-facing label.
    public var label: String {
        switch self {
        case .watcher: return "Viewer"
        case .collaborator: return "Editor"
        case .manager: return "Admin"
        }
    }

    /// Viewers are read-only; editors and admins can modify content.
    public var canEdit: Bool { self != .watcher }
    /// Only admins can edit settings/schema and delete.
    public var canManage: Bool { self == .manager }
}

// MARK: - ShareLink

/// A tokenized share link for a list or document.
public struct ShareLink: Sendable, Equatable, Hashable, Identifiable {
    public let token: String
    public let url: URL?
    public let role: ShareRole
    public let expiresAt: Date?
    public let createdAt: Date?
    public let revokedAt: Date?

    public var id: String { token }

    /// `true` once the link has been revoked (the server stops resolving it).
    public var isRevoked: Bool { revokedAt != nil }

    public init(
        token: String,
        url: URL? = nil,
        role: ShareRole,
        expiresAt: Date? = nil,
        createdAt: Date? = nil,
        revokedAt: Date? = nil
    ) {
        self.token = token
        self.url = url
        self.role = role
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.revokedAt = revokedAt
    }
}

extension ShareLink {
    public init(from dto: ShareLinkDTO) {
        self.init(
            token: dto.token,
            url: dto.url.flatMap(URL.init(string:)),
            role: ShareRole(rawValue: dto.role) ?? .watcher,
            expiresAt: dto.expiresAt,
            createdAt: dto.createdAt,
            revokedAt: dto.revokedAt
        )
    }
}

// MARK: - ResolvedShare

/// The result of resolving a share token — the role it grants, whether the
/// caller can/must claim it, and a lightweight view of the shared resource.
public struct ResolvedShare: Sendable, Equatable {
    public enum Resource: Sendable, Equatable {
        case list(id: String, title: String, description: String?, isPublic: Bool)
        case document(id: String, title: String, isPublic: Bool)

        public var id: String {
            switch self {
            case .list(let id, _, _, _): return id
            case .document(let id, _, _): return id
            }
        }
        public var title: String {
            switch self {
            case .list(_, let title, _, _): return title
            case .document(_, let title, _): return title
            }
        }
    }

    public let role: ShareRole
    public let canClaim: Bool
    public let needsAuth: Bool
    public let resource: Resource?

    public init(role: ShareRole, canClaim: Bool, needsAuth: Bool, resource: Resource?) {
        self.role = role
        self.canClaim = canClaim
        self.needsAuth = needsAuth
        self.resource = resource
    }
}

extension ResolvedShare {
    public init(from dto: ResolvedListShareDTO) {
        self.init(
            role: ShareRole(rawValue: dto.role) ?? .watcher,
            canClaim: dto.canClaim ?? false,
            needsAuth: dto.needsAuth ?? false,
            resource: dto.list.map {
                .list(id: $0.id, title: $0.title, description: $0.description, isPublic: $0.isPublic ?? false)
            }
        )
    }

    public init(from dto: ResolvedDocumentShareDTO) {
        self.init(
            role: ShareRole(rawValue: dto.role) ?? .watcher,
            canClaim: dto.canClaim ?? false,
            needsAuth: dto.needsAuth ?? false,
            resource: dto.document.map {
                .document(id: $0.id, title: $0.title, isPublic: $0.isPublic ?? false)
            }
        )
    }
}

// MARK: - ShareClaim

/// The result of claiming an edit/admin share link.
public struct ShareClaim: Sendable, Equatable {
    public let resourceId: String?
    public let role: ShareRole?

    public init(resourceId: String?, role: ShareRole?) {
        self.resourceId = resourceId
        self.role = role
    }
}

// MARK: - Collaborator

/// A person granted per-person access to a document (the list analogue is a
/// watcher). Surfaced in the sharing dialog's "Users with access" section.
public struct Collaborator: Sendable, Equatable, Hashable, Identifiable {
    public let userId: String
    public let role: ShareRole
    public let username: String?
    public let displayName: String?
    public let avatar: URL?
    public let createdAt: Date?

    public var id: String { userId }

    /// Best available human label: display name, then `username`, then a fallback.
    public var displayLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return "User"
    }

    public init(userId: String, role: ShareRole, username: String? = nil, displayName: String? = nil, avatar: URL? = nil, createdAt: Date? = nil) {
        self.userId = userId
        self.role = role
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.createdAt = createdAt
    }
}

extension Collaborator {
    /// Maps either the nested-`user` shape or the flat-field shape (see the ⚠️
    /// note on `CollaboratorDTO`).
    public init(from dto: CollaboratorDTO) {
        self.init(
            userId: dto.userId,
            role: ShareRole(rawValue: dto.role) ?? .watcher,
            username: dto.user?.username ?? dto.username,
            displayName: dto.user?.displayName ?? dto.displayName,
            avatar: (dto.user?.avatar ?? dto.avatar).flatMap(URL.init(string:)),
            createdAt: dto.createdAt
        )
    }
}

// MARK: - CollaboratorCandidate

/// A user surfaced by the collaborator search, eligible to be granted access.
public struct CollaboratorCandidate: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let email: String?
    public let avatar: URL?

    public var displayLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return email ?? "User"
    }

    public init(id: String, username: String? = nil, displayName: String? = nil, email: String? = nil, avatar: URL? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.avatar = avatar
    }
}

extension CollaboratorCandidate {
    public init(from dto: CollaboratorUserDTO) {
        self.init(
            id: dto.id,
            username: dto.username,
            displayName: dto.displayName,
            email: dto.email,
            avatar: dto.avatar.flatMap(URL.init(string:))
        )
    }
}

// MARK: - ShareInvite

/// A pending or accepted email invite for a list or document — the sharing
/// dialog's "Invite by email" section.
public struct ShareInvite: Sendable, Equatable, Hashable, Identifiable {
    public let token: String
    public let email: String
    public let role: ShareRole
    public let expiresAt: Date?
    public let accepted: Bool
    public let createdAt: Date?

    public var id: String { token }

    public init(token: String, email: String, role: ShareRole, expiresAt: Date? = nil, accepted: Bool = false, createdAt: Date? = nil) {
        self.token = token
        self.email = email
        self.role = role
        self.expiresAt = expiresAt
        self.accepted = accepted
        self.createdAt = createdAt
    }
}

extension ShareInvite {
    public init(from dto: ShareInviteDTO) {
        self.init(
            token: dto.token,
            email: dto.email,
            role: ShareRole(rawValue: dto.role) ?? .watcher,
            expiresAt: dto.expiresAt,
            accepted: dto.accepted ?? false,
            createdAt: dto.createdAt
        )
    }
}

// MARK: - SentInvite

/// The immediate result of sending an email invite — carries the claim `url`
/// so the UI can offer to copy it. The full pending-invite row appears on the
/// next `…Invites` list fetch.
public struct SentInvite: Sendable, Equatable {
    public let email: String
    public let role: ShareRole
    public let expiresAt: Date?
    public let url: URL?

    public init(email: String, role: ShareRole, expiresAt: Date? = nil, url: URL? = nil) {
        self.email = email
        self.role = role
        self.expiresAt = expiresAt
        self.url = url
    }
}

extension SentInvite {
    public init(from dto: CreateInviteResponse) {
        self.init(
            email: dto.email,
            role: ShareRole(rawValue: dto.role) ?? .watcher,
            expiresAt: dto.expiresAt,
            url: dto.url.flatMap(URL.init(string:))
        )
    }
}
