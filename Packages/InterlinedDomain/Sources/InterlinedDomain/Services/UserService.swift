import Foundation
import InterlinedKit

// MARK: - UserServicing

/// The account-self surface the App layer codes against for linked identities
/// and org membership (PLAN.md §1 "Profile & account / linked identities",
/// "Organizations" / org switcher, §6 M6).
///
/// Introduced this wave per the api-coverage footnote calling for a dedicated
/// service wrapping `User.identities` and `User.organizations` (both
/// session-only per decision 0001 — the kit builders already declare
/// `.session`, so this service just maps the envelopes to domain values).
///
/// Follows the same DI shape as the other domain services. Per decision 0003
/// every method returns domain values (`LinkedIdentity` / `UserOrganization`);
/// the kit DTOs never cross the seam.
public protocol UserServicing: Sendable {

    /// Loads the signed-in account's linked OAuth identities (GitHub,
    /// Mastodon, Bluesky, LinkedIn). Returns the mapped domain values; the
    /// `{ identities: [...] }` envelope is internal.
    func identities() async throws -> [LinkedIdentity]

    /// Loads the organizations the signed-in user belongs to, with their own
    /// membership role and joined-at. Powers the org switcher. The
    /// `{ organizations: [...] }` envelope is internal.
    func organizations() async throws -> [UserOrganization]

    /// Resolves the web authorize URL for linking a new OAuth identity
    /// (PLAN.md §4 — "OAuth … link-account-only in v1"; Wave 7 spike
    /// `docs/spikes/0002-oauth-identity-linking.md`). The v1 UX is a browser
    /// handoff: the App layer opens this URL in the user's default browser and
    /// the user returns and refreshes once the link completes.
    ///
    /// The URL is built from the kit's `Auth.authorize(provider:link:instance:)`
    /// builder (with `link: true`) resolved against the service's configured
    /// base URL — so the App layer obtains a ready-to-open `URL` without
    /// importing `InterlinedKit` (decision 0003).
    ///
    /// - Parameters:
    ///   - provider: the provider to link. `.other` providers have no authorize
    ///     route and throw `UserServiceError.unsupportedProvider`.
    ///   - instance: the Mastodon instance host (e.g. `mastodon.social`).
    ///     **Required for `.mastodon`** — a `nil`/blank instance throws
    ///     `UserServiceError.mastodonInstanceRequired`. Ignored by other
    ///     providers.
    /// - Throws: `UserServiceError` for an unsupported provider, a missing
    ///   Mastodon instance, or a URL that cannot be assembled.
    func identityLinkURL(provider: IdentityProvider, instance: String?) throws -> URL
}

// MARK: - UserServiceError

/// Errors surfaced by `UserService` for client-side preconditions that fail
/// before any network call (so the App layer can present a precise message).
public enum UserServiceError: Error, Equatable, Sendable {

    /// The provider has no OAuth authorize route the client can build
    /// (an `IdentityProvider.other(_)` token).
    case unsupportedProvider(String)

    /// Mastodon linking was requested without an instance host.
    case mastodonInstanceRequired

    /// The authorize URL could not be assembled from the base URL + path.
    case malformedLinkURL
}

// MARK: - UserService

public final class UserService: UserServicing {

    private let api: APIClientProtocol

    /// The site origin OAuth authorize URLs are resolved against. Defaults to
    /// the production host (matching `APIClient`'s default `baseURL`); tests
    /// inject a stub origin so the assembled URL is deterministic.
    private let baseURL: URL

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    ///   - baseURL: the site origin used only to resolve the OAuth authorize
    ///     URL (browser-handoff link flow). Defaults to the production host,
    ///     so existing composition-root call sites (`UserService(api:)`) are
    ///     unaffected.
    public init(
        api: APIClientProtocol,
        baseURL: URL = URL(string: "https://interlinedlist.com")!
    ) {
        self.api = api
        self.baseURL = baseURL
    }

    public func identities() async throws -> [LinkedIdentity] {
        let response = try await api.send(User.identities())
        return response.identities.map(LinkedIdentity.init(from:))
    }

    public func organizations() async throws -> [UserOrganization] {
        let response = try await api.send(User.organizations())
        return response.organizations.map(UserOrganization.init(from:))
    }

    public func identityLinkURL(provider: IdentityProvider, instance: String?) throws -> URL {
        // Map the domain provider onto the kit's OAuth path segment. `.other`
        // has no authorize route — reject it before building anything.
        let oauthProvider: OAuthProvider
        switch provider {
        case .github:   oauthProvider = .github
        case .mastodon: oauthProvider = .mastodon
        case .bluesky:  oauthProvider = .bluesky
        case .linkedin: oauthProvider = .linkedin
        case .other(let token):
            throw UserServiceError.unsupportedProvider(token)
        }

        // Mastodon requires an instance host; a blank one is treated as absent
        // so the server doesn't bounce us to `…/login?error=Instance…`.
        var resolvedInstance: String?
        if oauthProvider == .mastodon {
            let trimmed = instance?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else {
                throw UserServiceError.mastodonInstanceRequired
            }
            resolvedInstance = trimmed
        }

        // Reuse the kit's authorize builder (with `link: true`) for the path +
        // query, then resolve it against our configured origin. The builder is
        // total and never throws, so the only failure here is URL assembly.
        let request = Auth.authorize(
            provider: oauthProvider,
            link: true,
            instance: resolvedInstance
        )

        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw UserServiceError.malformedLinkURL
        }
        let basePath = baseURL.path.hasSuffix("/")
            ? String(baseURL.path.dropLast())
            : baseURL.path
        components.path = basePath
            + (request.path.hasPrefix("/") ? request.path : "/" + request.path)
        let queryItems = request.query.compactMap { item -> URLQueryItem? in
            guard let value = item.value else { return nil }
            return URLQueryItem(name: item.name, value: value)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw UserServiceError.malformedLinkURL
        }
        return url
    }
}
