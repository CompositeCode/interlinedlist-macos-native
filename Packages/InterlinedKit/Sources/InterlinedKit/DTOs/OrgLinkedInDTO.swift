import Foundation

// MARK: - Organization LinkedIn DTOs (work-consolidation.md G25)
//
// The organization-bound half of LinkedIn: an owner or admin connects one
// shared org credential, LinkedIn's company pages are stored on the org, and
// members are assigned individual pages to publish to.
//
// **What was verified, and how** (2026-09-09, read-only — the account is
// shared with concurrent sessions, so no write was ever issued):
//
//   OPTIONS /api/organizations/{id}/linkedin/status      -> Allow: GET, HEAD, OPTIONS
//   OPTIONS /api/organizations/{id}/linkedin/sync-pages  -> Allow: OPTIONS, POST
//   OPTIONS /api/organizations/{id}/linkedin/assignments -> Allow: OPTIONS, PUT
//   OPTIONS /api/organizations/{id}/linkedin/credential  -> Allow: DELETE, OPTIONS
//
// `GET /api/openapi.json` agrees exactly, and marks all four
// `x-auth-type: sync-token` — so they are Bearer routes, not session-only.
//
// ⚠️ `/help/api/organizations` additionally documents `GET` on `sync-pages`
// and `assignments`. **Those GETs are not deployed**: both answer HTTP 405
// live, and the OpenAPI document lists only the write verb for each. The help
// page is stale; OPTIONS + OpenAPI agree with each other and with the server.
// The practical consequence is that the discovered page list and the current
// assignments can only be read from `linkedin/status` — there is no separate
// read route — which is why `OrgLinkedInStatusResponse` below is the one type
// that has to carry them.
//
// The one live body observed (test account is a plain `member` of the org,
// and no org credential is connected on this tenant):
//
//   GET /api/organizations/{id}/linkedin/status
//       -> {"credential":null,"role":"member"}
//
// A *connected* status body could not be observed — no org reachable from the
// test account has a credential. `/help/api/organizations` describes it as
// `{ "connected": true, "expiresAt": "..." }` "plus the discovered pages".
// Rather than guess one spelling, every field below is optional and both
// spellings are accepted, so the type decodes the observed body, the
// documented body, or a mixture, and can never fail closed on a shape the
// client has not seen. `isConnected` folds the two spellings into one answer.

// MARK: - OrgLinkedInPageDTO

/// A LinkedIn company page discovered for an organization.
///
/// Field names follow the personal-page shape documented on
/// `/help/api/linkedin-integration` (`id` / `linkedInPageId` / `pageName` /
/// `pageLogoUrl` / `lastSyncedAt`), with `name` and `logoUrl` accepted as
/// alternates because the org-scoped page shape is not separately documented.
public struct OrgLinkedInPageDTO: Codable, Sendable, Equatable, Identifiable {

    /// The InterlinedList `OrgLinkedInPage` record id — the value that goes in
    /// an assignment's `pageId`.
    public let id: String
    /// LinkedIn's own identifier for the page.
    public let linkedInPageId: String?
    /// Display name of the company page.
    public let pageName: String?
    /// Page logo URL.
    public let pageLogoUrl: String?
    /// When the page was last re-discovered from LinkedIn.
    public let lastSyncedAt: Date?

    public init(
        id: String,
        linkedInPageId: String? = nil,
        pageName: String? = nil,
        pageLogoUrl: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.linkedInPageId = linkedInPageId
        self.pageName = pageName
        self.pageLogoUrl = pageLogoUrl
        self.lastSyncedAt = lastSyncedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, pageId
        case linkedInPageId
        case pageName, name, label
        case pageLogoUrl, logoUrl
        case lastSyncedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .id) {
            self.id = id
        } else {
            self.id = try c.decode(String.self, forKey: .pageId)
        }
        linkedInPageId = try c.decodeIfPresent(String.self, forKey: .linkedInPageId)
        pageName = try c.decodeIfPresent(String.self, forKey: .pageName)
            ?? c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decodeIfPresent(String.self, forKey: .label)
        pageLogoUrl = try c.decodeIfPresent(String.self, forKey: .pageLogoUrl)
            ?? c.decodeIfPresent(String.self, forKey: .logoUrl)
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(linkedInPageId, forKey: .linkedInPageId)
        try c.encodeIfPresent(pageName, forKey: .pageName)
        try c.encodeIfPresent(pageLogoUrl, forKey: .pageLogoUrl)
        try c.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
    }
}

// MARK: - OrgLinkedInAssignmentDTO

/// Which member is assigned to publish to which company page.
public struct OrgLinkedInAssignmentDTO: Codable, Sendable, Equatable {
    public let userId: String
    public let pageId: String?
    /// Denormalized page name, when the server includes it.
    public let pageName: String?

    public init(userId: String, pageId: String? = nil, pageName: String? = nil) {
        self.userId = userId
        self.pageId = pageId
        self.pageName = pageName
    }
}

// MARK: - OrgLinkedInCredentialDTO

/// The shared org credential, when one is connected.
public struct OrgLinkedInCredentialDTO: Codable, Sendable, Equatable {
    /// When the stored LinkedIn token expires.
    public let expiresAt: Date?
    /// Who connected the credential, when the server says.
    public let connectedByUserId: String?
    public let connectedAt: Date?

    public init(
        expiresAt: Date? = nil,
        connectedByUserId: String? = nil,
        connectedAt: Date? = nil
    ) {
        self.expiresAt = expiresAt
        self.connectedByUserId = connectedByUserId
        self.connectedAt = connectedAt
    }
}

// MARK: - OrgLinkedInStatusResponse

/// `GET /api/organizations/[id]/linkedin/status`.
///
/// Observed live as `{"credential":null,"role":"member"}`; documented as
/// `{ "connected": true, "expiresAt": "..." }` plus the discovered pages.
/// Every field is optional so either body — or a mixture — decodes.
public struct OrgLinkedInStatusResponse: Codable, Sendable, Equatable {

    /// The connected credential. `nil` (and present as JSON `null`) when the
    /// org has no shared LinkedIn credential. This is the **observed** shape.
    public let credential: OrgLinkedInCredentialDTO?

    /// The caller's role in the org, as the status route reports it. Lets the
    /// client gate the connect / disconnect controls without a second read.
    public let role: String?

    /// The documented boolean. Absent from the observed body.
    public let connected: Bool?

    /// Credential expiry, when the server flattens it onto the status instead
    /// of nesting it under `credential`.
    public let expiresAt: Date?

    /// The company pages stored on the org. Absent when nothing is connected.
    /// This is the only route that returns them — `GET` on `sync-pages` is 405.
    public let pages: [OrgLinkedInPageDTO]?

    /// Current page assignments, when the status route includes them.
    public let assignments: [OrgLinkedInAssignmentDTO]?

    public init(
        credential: OrgLinkedInCredentialDTO? = nil,
        role: String? = nil,
        connected: Bool? = nil,
        expiresAt: Date? = nil,
        pages: [OrgLinkedInPageDTO]? = nil,
        assignments: [OrgLinkedInAssignmentDTO]? = nil
    ) {
        self.credential = credential
        self.role = role
        self.connected = connected
        self.expiresAt = expiresAt
        self.pages = pages
        self.assignments = assignments
    }

    /// Whether the org has a usable shared credential. Prefers the explicit
    /// `connected` boolean when the server sends it, and otherwise infers it
    /// from the presence of `credential` — which is what the live body uses.
    public var isConnected: Bool {
        connected ?? (credential != nil)
    }
}

// MARK: - Request bodies

/// `PUT /api/organizations/[id]/linkedin/assignments` body.
///
/// VERIFIED 2026-09-09 from `GET /api/openapi.json`: the
/// `putOrganizationsByIdLinkedinAssignments` operation declares exactly two
/// body properties, `userId` and `pageId`, both strings.
///
/// ⚠️ This contradicts `/help/api/organizations`, which calls the same route
/// "Replace the assignment map atomically". The OpenAPI document is generated
/// from the deployed handlers and has already been shown to beat the help page
/// on this resource (the help page also documents two GETs that answer 405),
/// so the client sends **one assignment per call**. Clearing an assignment is
/// modelled as a `nil` `pageId`; that is the least-surprising reading of a
/// nullable page reference, but it is the one part of this body that could not
/// be confirmed from either source.
public struct UpdateOrgLinkedInAssignmentRequest: Codable, Sendable, Equatable {
    public let userId: String
    public let pageId: String?

    public init(userId: String, pageId: String?) {
        self.userId = userId
        self.pageId = pageId
    }
}
