import Foundation

// MARK: - UserResponse

/// Envelope for `GET /api/user` — the live API nests the account under a
/// top-level `user` key: `{ "user": { ... /// One row in the `GET /api/user/engagement` recent feed. Structurally a
/// notification: the aggregate view is built from the same records.
public struct UserEngagementItemDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let body: String?
    public let type: String?
    public let sourceMessageId: String?
    public let createdAt: Date?
    public let routePath: String?

    public init(
        id: String,
        title: String? = nil,
        body: String? = nil,
        type: String? = nil,
        sourceMessageId: String? = nil,
        createdAt: Date? = nil,
        routePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.type = type
        self.sourceMessageId = sourceMessageId
        self.createdAt = createdAt
        self.routePath = routePath
    }
}

/// `GET /api/user/engagement` response — lifetime dig / push totals on your own
/// messages plus the most recent engagement events (work-consolidation.md G27).
///
/// VERIFIED live 2026-09-06: returned
/// `{"totalDigs":24,"totalPushes":6,"recent":[ …10 items… ]}`.
public struct UserEngagementResponse: Codable, Sendable, Equatable {
    public let totalDigs: Int
    public let totalPushes: Int
    public let recent: [UserEngagementItemDTO]

    public init(totalDigs: Int, totalPushes: Int, recent: [UserEngagementItemDTO] = []) {
        self.totalDigs = totalDigs
        self.totalPushes = totalPushes
        self.recent = recent
    }
}

// MARK: - Request bodies }`.
public struct UserResponse: Decodable, Sendable, Equatable {
    public let user: UserDTO

    public init(user: UserDTO) {
        self.user = user
    }
}

// MARK: - UserDTO

/// The authenticated account, as returned by `GET /api/user` (nested under
/// `user`) and by `POST /api/user/update`.
///
/// `customerStatus` is the field the future `EntitlementsService` reads to gate
/// subscriber features (PLAN.md §3, §1 "Subscriber gating"). It is kept as a
/// raw `String` here so the DTO stays a faithful mirror of the wire shape;
/// mapping it to a typed enum is a Domain-layer concern.
///
/// Many account fields are nullable on the wire (`pendingEmail`, `latitude`,
/// API keys, etc.) and are modelled as optionals. Sensitive fields such as
/// `openaiApiKey` / `anthropicApiKey` are decoded for round-trip fidelity but
/// must never be logged.
public struct UserDTO: Decodable, Sendable, Equatable {
    public let id: String
    public let email: String
    public let username: String
    public let displayName: String?
    public let avatar: String?
    public let bio: String?
    public let theme: String?
    public let emailVerified: Bool
    public let pendingEmail: String?
    public let maxMessageLength: Int?
    public let defaultPubliclyVisible: Bool?
    public let messagesPerPage: Int?
    public let viewingPreference: String?
    public let showPreviews: Bool?
    public let showAdvancedPostSettings: Bool?
    public let latitude: Double?
    public let longitude: Double?
    public let isPrivateAccount: Bool?
    public let cleared: Bool?
    public let githubDefaultRepo: String?
    public let openaiApiKey: String?
    public let anthropicApiKey: String?
    public let customerStatus: String
    /// The account's lifecycle status (`new` / `active` / `restricted` /
    /// `suspended` / `banned`), verified live 2026-09-09 on `GET /api/user`.
    ///
    /// Optional and kept as a raw `String` on purpose. The OpenAPI schema
    /// declares this as a bare `{"type":"string"}` with **no** enum, so the
    /// server may introduce a value this client has never seen — decoding it
    /// loosely means an unknown status can never fail the whole account decode.
    /// `InterlinedDomain.AccountStatus` narrows it and fails open.
    public let accountStatus: String?
    public let stripeCustomerId: String?
    public let notificationTrayLimit: Int?
    public let createdAt: Date
    public let isAdministrator: Bool?

    public init(
        id: String,
        email: String,
        username: String,
        displayName: String? = nil,
        avatar: String? = nil,
        bio: String? = nil,
        theme: String? = nil,
        emailVerified: Bool,
        pendingEmail: String? = nil,
        maxMessageLength: Int? = nil,
        defaultPubliclyVisible: Bool? = nil,
        messagesPerPage: Int? = nil,
        viewingPreference: String? = nil,
        showPreviews: Bool? = nil,
        showAdvancedPostSettings: Bool? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isPrivateAccount: Bool? = nil,
        cleared: Bool? = nil,
        githubDefaultRepo: String? = nil,
        openaiApiKey: String? = nil,
        anthropicApiKey: String? = nil,
        customerStatus: String,
        accountStatus: String? = nil,
        stripeCustomerId: String? = nil,
        notificationTrayLimit: Int? = nil,
        createdAt: Date,
        isAdministrator: Bool? = nil
    ) {
        self.id = id
        self.email = email
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.bio = bio
        self.theme = theme
        self.emailVerified = emailVerified
        self.pendingEmail = pendingEmail
        self.maxMessageLength = maxMessageLength
        self.defaultPubliclyVisible = defaultPubliclyVisible
        self.messagesPerPage = messagesPerPage
        self.viewingPreference = viewingPreference
        self.showPreviews = showPreviews
        self.showAdvancedPostSettings = showAdvancedPostSettings
        self.latitude = latitude
        self.longitude = longitude
        self.isPrivateAccount = isPrivateAccount
        self.cleared = cleared
        self.githubDefaultRepo = githubDefaultRepo
        self.openaiApiKey = openaiApiKey
        self.anthropicApiKey = anthropicApiKey
        self.customerStatus = customerStatus
        self.accountStatus = accountStatus
        self.stripeCustomerId = stripeCustomerId
        self.notificationTrayLimit = notificationTrayLimit
        self.createdAt = createdAt
        self.isAdministrator = isAdministrator
    }
}

// MARK: - UpdateUserRequest

/// Request body for `PATCH /api/user/update`. Every field is optional so a
/// caller patches only what changed; nil fields are omitted from the wire body.
///
/// VERIFIED live 2026-09-09 (work-consolidation.md G35 / issue #43): the web
/// client's own "View Preferences" card PATCHes exactly
/// `{ messagesPerPage, viewingPreference, showPreviews, notificationTrayLimit }`
/// to this route, which settles two open questions — `notificationTrayLimit` is
/// an accepted key here (it was previously read-only on `UserDTO`), and
/// `viewingPreference` is a snake_case token, not a display string. The web
/// validates `messagesPerPage` to 10...30 and `notificationTrayLimit` to
/// 10...40 before sending; `UserSettings` clamps to the same ranges so a value
/// saved from macOS is always representable on the web.
public struct UpdateUserRequest: Encodable, Sendable, Equatable {
    public let displayName: String?
    public let bio: String?
    public let theme: String?
    public let defaultPubliclyVisible: Bool?
    public let messagesPerPage: Int?
    public let viewingPreference: String?
    public let showPreviews: Bool?
    public let showAdvancedPostSettings: Bool?
    public let isPrivateAccount: Bool?
    /// How many rows the notification bell tray holds (10...40, default 20).
    /// Accepted by this route — confirmed against the web client's own PATCH
    /// body on 2026-09-09.
    public let notificationTrayLimit: Int?

    /// The account's own per-message character cap.
    ///
    /// On `UserDTO` since the field existed and **absent from this request**, so
    /// the value was readable and unwritable (GitHub #46). Verified live
    /// 2026-09-15: the server accepts `1...10000` and rejects anything outside
    /// it with `400 "maxMessageLength must be a positive integer between 1 and
    /// 10000"`. It accepts a numeric string too; a number is sent because that
    /// is what the field is.
    ///
    /// - Important: this is the **user's own** cap, not the platform's.
    ///   `GET /api/limits` reports `message.maxContentLength: 5000`, and the
    ///   account range reaches 10000 — so a user can set a cap *above* the
    ///   platform ceiling and the composer must honour the lower of the two.
    public let maxMessageLength: Int?

    public init(
        displayName: String? = nil,
        bio: String? = nil,
        theme: String? = nil,
        defaultPubliclyVisible: Bool? = nil,
        messagesPerPage: Int? = nil,
        viewingPreference: String? = nil,
        showPreviews: Bool? = nil,
        showAdvancedPostSettings: Bool? = nil,
        isPrivateAccount: Bool? = nil,
        notificationTrayLimit: Int? = nil,
        maxMessageLength: Int? = nil
    ) {
        self.displayName = displayName
        self.bio = bio
        self.theme = theme
        self.defaultPubliclyVisible = defaultPubliclyVisible
        self.messagesPerPage = messagesPerPage
        self.viewingPreference = viewingPreference
        self.showPreviews = showPreviews
        self.showAdvancedPostSettings = showAdvancedPostSettings
        self.isPrivateAccount = isPrivateAccount
        self.notificationTrayLimit = notificationTrayLimit
        self.maxMessageLength = maxMessageLength
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, bio, theme, defaultPubliclyVisible, messagesPerPage
        case viewingPreference, showPreviews, showAdvancedPostSettings, isPrivateAccount
        case notificationTrayLimit, maxMessageLength
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(theme, forKey: .theme)
        try container.encodeIfPresent(defaultPubliclyVisible, forKey: .defaultPubliclyVisible)
        try container.encodeIfPresent(messagesPerPage, forKey: .messagesPerPage)
        try container.encodeIfPresent(viewingPreference, forKey: .viewingPreference)
        try container.encodeIfPresent(showPreviews, forKey: .showPreviews)
        try container.encodeIfPresent(showAdvancedPostSettings, forKey: .showAdvancedPostSettings)
        try container.encodeIfPresent(maxMessageLength, forKey: .maxMessageLength)
        try container.encodeIfPresent(isPrivateAccount, forKey: .isPrivateAccount)
        try container.encodeIfPresent(notificationTrayLimit, forKey: .notificationTrayLimit)
    }
}

// MARK: - AvatarFromURLRequest

/// Request body for `POST /api/user/avatar/from-url`: `{ "url": "string" }`.
public struct AvatarFromURLRequest: Encodable, Sendable, Equatable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

// MARK: - ChangeEmailRequest

/// Request body for `POST /api/user/change-email/request`. The user supplies
/// the new address (and, on most accounts, confirms with the current password).
public struct ChangeEmailRequest: Encodable, Sendable, Equatable {
    public let newEmail: String
    public let password: String?

    public init(newEmail: String, password: String? = nil) {
        self.newEmail = newEmail
        self.password = password
    }

    private enum CodingKeys: String, CodingKey {
        case newEmail, password
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(newEmail, forKey: .newEmail)
        try container.encodeIfPresent(password, forKey: .password)
    }
}

// MARK: - DeleteAccountRequest

/// Request body for `POST /api/user/delete`. Account deletion is typically
/// password-confirmed; the field is optional so callers on password-less
/// flows (OAuth-only accounts) can omit it.
public struct DeleteAccountRequest: Encodable, Sendable, Equatable {
    public let password: String?

    public init(password: String? = nil) {
        self.password = password
    }

    private enum CodingKeys: String, CodingKey {
        case password
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(password, forKey: .password)
    }
}

// MARK: - Identities

/// Envelope for `GET /api/user/identities` (session-only): `{ "identities": [...] }`.
public struct IdentitiesResponse: Decodable, Sendable, Equatable {
    public let identities: [LinkedIdentityDTO]

    public init(identities: [LinkedIdentityDTO]) {
        self.identities = identities
    }
}

/// Request body for `POST /api/user/identities/verify`.
public struct VerifyIdentityRequest: Encodable, Sendable, Equatable {
    public let provider: String

    public init(provider: String) {
        self.provider = provider
    }
}

/// Response of `POST /api/user/identities/verify`.
///
/// Every field is optional and the shape is read permissively: the verify write
/// was **not exercised live** — it mutates a shared recon account's connection
/// state — so this follows the documented action rather than a capture. The
/// fields are named for what `/help/settings` describes Verify as doing.
/// Tighten once a real response is seen; until then a missing key degrades one
/// field rather than failing the call, and `isVerified` falls back to "the call
/// succeeded", which is the only thing the status code really tells us.
public struct VerifyIdentityResponse: Decodable, Sendable, Equatable {
    public let verified: Bool?
    public let provider: String?
    public let message: String?
    public let lastVerifiedAt: Date?

    public init(
        verified: Bool? = nil,
        provider: String? = nil,
        message: String? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.verified = verified
        self.provider = provider
        self.message = message
        self.lastVerifiedAt = lastVerifiedAt
    }

    /// Whether the connection is live. A body with no `verified` key but a 2xx
    /// status counts as verified — the route answering at all is the signal.
    public var isVerified: Bool { verified ?? true }
}

/// A single linked OAuth identity (GitHub, Mastodon, Bluesky, LinkedIn, X).
public struct LinkedIdentityDTO: Decodable, Sendable, Equatable {
    public let id: String
    public let provider: String
    public let providerUsername: String?
    public let profileUrl: String?
    public let avatarUrl: String?
    public let connectedAt: Date?
    public let lastVerifiedAt: Date?

    public init(
        id: String,
        provider: String,
        providerUsername: String? = nil,
        profileUrl: String? = nil,
        avatarUrl: String? = nil,
        connectedAt: Date? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.providerUsername = providerUsername
        self.profileUrl = profileUrl
        self.avatarUrl = avatarUrl
        self.connectedAt = connectedAt
        self.lastVerifiedAt = lastVerifiedAt
    }
}

// MARK: - Organizations (user membership view)

/// Envelope for `GET /api/user/organizations` (`x-auth-type: sync-token` —
/// Bearer-reachable; probed 2026-09-09, correcting an earlier "session-only" note):
/// `{ "organizations": [...] }`. Each entry carries the caller's membership
/// `role` and `joinedAt` alongside the organization fields.
public struct UserOrganizationsResponse: Decodable, Sendable, Equatable {
    public let organizations: [UserOrganizationDTO]

    public init(organizations: [UserOrganizationDTO]) {
        self.organizations = organizations
    }
}

/// An organization the user belongs to, with their membership metadata.
public struct UserOrganizationDTO: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let slug: String?
    public let description: String?
    public let avatar: String?
    public let isPublic: Bool?
    public let isSystem: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let deletedAt: Date?
    public let role: String
    public let joinedAt: Date?
    /// Duplicate of `role` the live route also emits. Verified 2026-09-09.
    public let userRole: String?
    /// Total members in the org, denormalized onto the membership row.
    /// Verified 2026-09-09; drives the My Organizations row subtitle.
    public let memberCount: Int?

    public init(
        id: String,
        name: String,
        slug: String? = nil,
        description: String? = nil,
        avatar: String? = nil,
        isPublic: Bool? = nil,
        isSystem: Bool? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        role: String,
        joinedAt: Date? = nil,
        userRole: String? = nil,
        memberCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.avatar = avatar
        self.isPublic = isPublic
        self.isSystem = isSystem
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.role = role
        self.joinedAt = joinedAt
        self.userRole = userRole
        self.memberCount = memberCount
    }
}

// MARK: - User search / lookup (NW-1)

/// A user as returned by `GET /api/users/search` and `GET /api/users/lookup`.
public struct UserSearchResultDTO: Decodable, Sendable, Equatable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatar: String?
    public let isPrivate: Bool

    public init(
        id: String,
        username: String,
        displayName: String? = nil,
        avatar: String? = nil,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.isPrivate = isPrivate
    }
}

/// Response envelope for `GET /api/users/search`.
public struct UserSearchResponse: Decodable, Sendable, Equatable {
    public let users: [UserSearchResultDTO]
    public let total: Int

    public init(users: [UserSearchResultDTO], total: Int) {
        self.users = users
        self.total = total
    }
}
