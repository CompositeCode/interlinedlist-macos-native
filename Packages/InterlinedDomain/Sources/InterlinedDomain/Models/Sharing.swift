import Foundation
import InterlinedKit

// MARK: - ShareRole

/// A share grant's capability level (the-gaps.md G3). Values match the live API
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
