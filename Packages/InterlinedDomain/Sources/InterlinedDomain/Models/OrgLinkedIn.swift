import Foundation
import InterlinedKit

// MARK: - Organization LinkedIn domain models (work-consolidation.md G25)
//
// The organization-bound half of LinkedIn: one shared credential per org, the
// company pages LinkedIn returns for it, and the per-member page assignments
// that decide where a member's cross-post actually lands.
//
// Why this matters more than it looks: per `/help/organizations`, a member who
// has an assignment gets the assigned company page as their *default* LinkedIn
// destination. Enabling LinkedIn cross-posting without picking a target then
// publishes to the company page, not their personal profile. The composer has
// to be able to say so.

// MARK: - OrgLinkedInPage

/// A LinkedIn company page discovered for an organization.
///
/// Domain projection of `InterlinedKit.OrgLinkedInPageDTO`. Per decision 0003
/// the DTO never crosses into the UI.
public struct OrgLinkedInPage: Sendable, Equatable, Hashable, Identifiable {

    /// The InterlinedList record id — the value an assignment refers to.
    public let id: String

    /// LinkedIn's own identifier for the page.
    public let linkedInPageId: String?

    /// Display name. Falls back to the LinkedIn page id, then the record id,
    /// so a page row is never blank.
    public let name: String

    public let logoURL: URL?

    public let lastSyncedAt: Date?

    public init(
        id: String,
        linkedInPageId: String? = nil,
        name: String,
        logoURL: URL? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.linkedInPageId = linkedInPageId
        self.name = name
        self.logoURL = logoURL
        self.lastSyncedAt = lastSyncedAt
    }
}

extension OrgLinkedInPage {
    public init(from dto: OrgLinkedInPageDTO) {
        let resolvedName = dto.pageName
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? dto.linkedInPageId
            ?? dto.id
        self.init(
            id: dto.id,
            linkedInPageId: dto.linkedInPageId,
            name: resolvedName,
            logoURL: dto.pageLogoUrl
                .flatMap { $0.isEmpty ? nil : $0 }
                .flatMap(URL.init(string:)),
            lastSyncedAt: dto.lastSyncedAt
        )
    }
}

// MARK: - OrgLinkedInAssignment

/// One member's company-page assignment.
public struct OrgLinkedInAssignment: Sendable, Equatable, Hashable, Identifiable {

    public let userId: String

    /// The assigned page's record id. `nil` means the member has no
    /// assignment and falls back to their personal LinkedIn identity.
    public let pageId: String?

    /// Denormalized page name, when the server supplied it.
    public let pageName: String?

    public var id: String { userId }

    public init(userId: String, pageId: String? = nil, pageName: String? = nil) {
        self.userId = userId
        self.pageId = pageId
        self.pageName = pageName
    }
}

extension OrgLinkedInAssignment {
    public init(from dto: OrgLinkedInAssignmentDTO) {
        self.init(userId: dto.userId, pageId: dto.pageId, pageName: dto.pageName)
    }
}

// MARK: - OrgLinkedInStatus

/// An organization's shared-LinkedIn state: whether a credential is connected,
/// what the caller may do about it, the discovered pages, and the assignments.
///
/// `pages` and `assignments` arrive on this value because there is no separate
/// read route for either — `GET` on `linkedin/sync-pages` and on
/// `linkedin/assignments` both answer 405 (see `OrgLinkedInDTO.swift`).
public struct OrgLinkedInStatus: Sendable, Equatable {

    /// Whether the org has a shared credential connected.
    public let isConnected: Bool

    /// When the stored credential expires, when known.
    public let expiresAt: Date?

    /// The caller's role in the org as the status route reports it. `nil` when
    /// the route omitted it; callers then fall back to the role they already
    /// hold from the membership list.
    public let callerRole: OrgRole?

    /// Company pages stored on the org. Empty when nothing is connected.
    public let pages: [OrgLinkedInPage]

    /// Current per-member assignments, when the server returned them.
    public let assignments: [OrgLinkedInAssignment]

    /// Whether the caller may connect / disconnect the credential and assign
    /// pages. Owners and admins only, per `/help/organizations`. An unknown
    /// role answers `false` — management controls stay hidden rather than
    /// rendering an action the server will reject.
    public var callerCanManage: Bool {
        switch callerRole {
        case .owner, .admin: return true
        case .member, .other, .none: return false
        }
    }

    public init(
        isConnected: Bool,
        expiresAt: Date? = nil,
        callerRole: OrgRole? = nil,
        pages: [OrgLinkedInPage] = [],
        assignments: [OrgLinkedInAssignment] = []
    ) {
        self.isConnected = isConnected
        self.expiresAt = expiresAt
        self.callerRole = callerRole
        self.pages = pages
        self.assignments = assignments
    }

    /// The disconnected boundary value.
    public static let disconnected = OrgLinkedInStatus(isConnected: false)

    /// The page assigned to a given member, if any.
    public func assignedPage(for userId: String) -> OrgLinkedInPage? {
        guard let pageId = assignments.first(where: { $0.userId == userId })?.pageId else {
            return nil
        }
        return pages.first { $0.id == pageId }
    }
}

extension OrgLinkedInStatus {
    public init(from dto: OrgLinkedInStatusResponse) {
        self.init(
            isConnected: dto.isConnected,
            // Expiry may be nested under `credential` or flattened onto the
            // status; take whichever the server sent.
            expiresAt: dto.credential?.expiresAt ?? dto.expiresAt,
            callerRole: dto.role.map(OrgRole.init(wireToken:)),
            pages: (dto.pages ?? []).map(OrgLinkedInPage.init(from:)),
            assignments: (dto.assignments ?? []).map(OrgLinkedInAssignment.init(from:))
        )
    }
}

// MARK: - OrgLinkedInAuthorization

/// Where to send the browser to connect an org's shared LinkedIn credential.
///
/// `GET /api/auth/linkedin/org-authorize?organizationId=…` is a browser
/// redirect flow (`x-auth-type: none` in the OpenAPI document), so the client
/// opens it rather than calling it — the same treatment the personal LinkedIn
/// link flow gets.
public enum OrgLinkedInAuthorization {

    /// Builds the org-authorize URL for `organizationId` against `baseURL`.
    /// Returns `nil` only if the components cannot form a URL.
    public static func url(baseURL: URL, organizationId: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/api/auth/linkedin/org-authorize"
        components.queryItems = [URLQueryItem(name: "organizationId", value: organizationId)]
        return components.url
    }
}
