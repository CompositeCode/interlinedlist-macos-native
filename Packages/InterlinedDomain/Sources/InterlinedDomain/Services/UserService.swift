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

    // MARK: - Account mutations (M7)

    /// Starts the email-change flow for the signed-in account. The server
    /// sends a confirmation link to `newEmail`; no local state changes until
    /// the user clicks the link. Throws on any networking failure.
    func requestEmailChange(newEmail: String) async throws

    /// Uploads raw image bytes and returns the hosted avatar URL. The server
    /// responds with a `MediaUploadResponse`; the returned `URL` is parsed
    /// from `response.url`. Returns `nil` when the server returns a URL string
    /// that cannot be parsed into a `Foundation.URL` (edge case).
    func uploadAvatar(imageData: Data, contentType: String) async throws -> URL?

    /// Permanently deletes the signed-in account. The server ignores the
    /// response body; callers should sign out immediately on success. Passes
    /// `password` to the `DeleteAccountRequest` so the server can re-confirm
    /// identity; `nil` is accepted by the endpoint but callers should always
    /// supply the current password.
    func deleteAccount(password: String) async throws

    // MARK: - User search / lookup (NW-1)

    /// Searches for users by username prefix. Returns the first `limit` matches.
    func searchUsers(query: String, limit: Int?) async throws -> [UserSearchResult]

    /// Looks up a user by exact username handle. Returns `nil` when the server
    /// responds `404` (user not found); throws for any other error.
    func lookupUser(handle: String) async throws -> UserSearchResult?

    // MARK: - Provider status (NW-4)

    /// Returns whether Bluesky OAuth is configured on the server.
    func blueskyConfigured() async throws -> Bool

    /// Returns whether Mastodon OAuth is configured for a given instance host.
    func mastodonConfigured(instance: String) async throws -> Bool

    // MARK: - Native OAuth linking (NW-5)

    /// Builds the authorize URL for a native in-app OAuth flow (NW-5). Like
    /// `identityLinkURL` but appends `redirect_uri=interlinedlist://oauth/callback`
    /// so `ASWebAuthenticationSession` can intercept the callback without opening
    /// the browser.
    func identityLinkURLNative(provider: IdentityProvider, instance: String?) throws -> URL

    /// Exchanges the one-time `code` + `state` returned by the native OAuth
    /// callback for a linked identity. Returns the new `LinkedIdentity` on
    /// success; throws on any API failure.
    func linkIdentityNative(
        provider: IdentityProvider,
        code: String,
        state: String
    ) async throws -> LinkedIdentity
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

    // MARK: - Account mutations (M7)

    public func requestEmailChange(newEmail: String) async throws {
        _ = try await api.send(User.requestEmailChange(ChangeEmailRequest(newEmail: newEmail)))
    }

    public func uploadAvatar(imageData: Data, contentType: String) async throws -> URL? {
        let response = try await api.send(User.uploadAvatar(imageData, contentType: contentType))
        let trimmed = response.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    public func deleteAccount(password: String) async throws {
        _ = try await api.send(User.delete(DeleteAccountRequest(password: password)))
    }

    // MARK: - User search / lookup (NW-1)

    public func searchUsers(query: String, limit: Int?) async throws -> [UserSearchResult] {
        let response = try await api.send(User.search(query: query, limit: limit))
        return response.users.map(UserSearchResult.init(from:))
    }

    public func lookupUser(handle: String) async throws -> UserSearchResult? {
        do {
            let dto = try await api.send(User.lookup(handle: handle))
            return UserSearchResult(from: dto)
        } catch let error as APIError {
            if case .notFound = error { return nil }
            throw error
        }
    }

    // MARK: - Provider status (NW-4)

    public func blueskyConfigured() async throws -> Bool {
        let response = try await api.send(Auth.blueskyStatus())
        return response.configured
    }

    public func mastodonConfigured(instance: String) async throws -> Bool {
        let response = try await api.send(Auth.mastodonStatus(instance: instance))
        return response.configured
    }

    // MARK: - Native OAuth linking (NW-5)

    public func identityLinkURLNative(provider: IdentityProvider, instance: String?) throws -> URL {
        let oauthProvider: OAuthProvider
        switch provider {
        case .github:   oauthProvider = .github
        case .mastodon: oauthProvider = .mastodon
        case .bluesky:  oauthProvider = .bluesky
        case .linkedin: oauthProvider = .linkedin
        case .other(let token):
            throw UserServiceError.unsupportedProvider(token)
        }

        var resolvedInstance: String?
        if oauthProvider == .mastodon {
            let trimmed = instance?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else {
                throw UserServiceError.mastodonInstanceRequired
            }
            resolvedInstance = trimmed
        }

        let request = Auth.authorize(
            provider: oauthProvider,
            link: true,
            instance: resolvedInstance,
            redirectURI: "interlinedlist://oauth/callback"
        )

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
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

    public func linkIdentityNative(
        provider: IdentityProvider,
        code: String,
        state: String
    ) async throws -> LinkedIdentity {
        let oauthProvider: OAuthProvider
        switch provider {
        case .github:   oauthProvider = .github
        case .mastodon: oauthProvider = .mastodon
        case .bluesky:  oauthProvider = .bluesky
        case .linkedin: oauthProvider = .linkedin
        case .other(let token):
            throw UserServiceError.unsupportedProvider(token)
        }

        let response = try await api.send(Auth.linkIdentity(provider: oauthProvider, code: code, state: state))
        return LinkedIdentity(
            id: response.providerUserId,
            provider: IdentityProvider(wireToken: response.provider),
            handle: response.username,
            profileURL: nil,
            avatarURL: nil,
            connectedAt: response.linkedAt,
            lastVerifiedAt: nil
        )
    }
}
