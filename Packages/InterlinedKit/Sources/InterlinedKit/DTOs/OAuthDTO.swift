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
