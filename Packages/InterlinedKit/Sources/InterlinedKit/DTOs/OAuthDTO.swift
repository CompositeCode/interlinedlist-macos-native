import Foundation

// MARK: - OAuthProvider

/// The identity providers InterlinedList supports for OAuth account linking and
/// cross-posting.
///
/// Each case maps to the `{provider}` path segment in
/// `GET /api/auth/{provider}/authorize` (and the matching `…/callback`). The
/// raw value is the exact path segment the live API expects, verified by the
/// Wave 7 OAuth spike (`docs/spikes/0002-oauth-identity-linking.md`):
///
/// - `github`   → 307 to `github.com/login/oauth/authorize` (PKCE, S256)
/// - `mastodon` → 307 to `<instance>/oauth/authorize` (requires an `instance`)
/// - `bluesky`  → 307 to `bsky.social/oauth/authorize` (AT-proto PAR/DPoP)
/// - `linkedin` → 307 to `linkedin.com/oauth/v2/authorization`
public enum OAuthProvider: String, Sendable, Equatable, CaseIterable {
    case github
    case mastodon
    case bluesky
    case linkedin
}

// MARK: - LinkedInStatusResponse

/// Response body for `GET /api/auth/linkedin/status` (public, no auth):
/// `{ "configured": true, "redirectUri": "https://…/api/auth/linkedin/callback" }`.
///
/// `redirectUri` is the **web** callback URL the LinkedIn OAuth app is
/// registered against — a `https://interlinedlist.com/…` URL, not a native
/// custom scheme. The Wave 7 spike treats this as the central evidence that the
/// `/authorize` flows are not natively completable as-is; see
/// `docs/spikes/0002-oauth-identity-linking.md`.
public struct LinkedInStatusResponse: Decodable, Sendable, Equatable {
    /// Whether the server has a LinkedIn OAuth client configured.
    public let configured: Bool
    /// The registered OAuth redirect/callback URL (a web URL on the
    /// `interlinedlist.com` domain).
    public let redirectUri: String

    public init(configured: Bool, redirectUri: String) {
        self.configured = configured
        self.redirectUri = redirectUri
    }
}

// MARK: - Provider status (NW-4)

/// Shared response for `GET /api/auth/bluesky/status` and
/// `GET /api/auth/mastodon/status` — both return `{ "configured": bool }`.
public struct ProviderStatusResponse: Decodable, Sendable, Equatable {
    public let configured: Bool

    public init(configured: Bool) {
        self.configured = configured
    }
}

// MARK: - Native OAuth link (NW-5)

/// Request body for `POST /api/auth/{provider}/link`.
public struct OAuthLinkRequest: Encodable, Sendable, Equatable {
    public let code: String
    public let state: String

    public init(code: String, state: String) {
        self.code = code
        self.state = state
    }
}

/// Response for `POST /api/auth/{provider}/link`.
public struct OAuthLinkResponse: Decodable, Sendable, Equatable {
    public let provider: String
    public let providerUserId: String
    public let username: String
    public let linkedAt: Date

    public init(provider: String, providerUserId: String, username: String, linkedAt: Date) {
        self.provider = provider
        self.providerUserId = providerUserId
        self.username = username
        self.linkedAt = linkedAt
    }
}
