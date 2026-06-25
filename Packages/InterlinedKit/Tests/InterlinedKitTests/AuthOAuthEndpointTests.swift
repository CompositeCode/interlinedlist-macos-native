import XCTest
@testable import InterlinedKit

/// BDD tests for the OAuth additions to the `Auth` endpoint namespace:
/// `Auth.authorize(provider:link:instance:)` for the four providers and
/// `Auth.linkedinStatus()`, plus `LinkedInStatusResponse` decoding.
///
/// These are pure builder-shape and decode tests — the `/authorize` endpoints
/// reply with a `307` redirect and no JSON body (verified by the Wave 7 spike,
/// `docs/spikes/0002-oauth-identity-linking.md`), so there is nothing to send
/// through the transport. The DTO fixture is the live, probed JSON.
final class AuthOAuthEndpointTests: XCTestCase {

    /// Query items that survive `QueryItem`'s nil-skipping, mirroring the
    /// `MessagesEndpointTests` convention.
    private func presentQuery(_ request: Request<some Any>) -> [QueryItem] {
        request.query.filter { $0.value != nil }
    }

    // MARK: - authorize: happy path (per provider)

    func test_givenGithubProvider_whenAuthorizeBuilt_thenTargetsProviderPathNoAuth() {
        let request = Auth.authorize(provider: .github)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/auth/github/authorize")
        XCTAssertEqual(request.auth, .none) // public per the live 307 to GitHub
        XCTAssertNil(request.body)
    }

    func test_givenBlueskyProvider_whenAuthorizeBuilt_thenTargetsProviderPath() {
        let request = Auth.authorize(provider: .bluesky)
        XCTAssertEqual(request.path, "/api/auth/bluesky/authorize")
        XCTAssertEqual(request.auth, .none)
    }

    func test_givenLinkedinProvider_whenAuthorizeBuilt_thenTargetsProviderPath() {
        let request = Auth.authorize(provider: .linkedin)
        XCTAssertEqual(request.path, "/api/auth/linkedin/authorize")
        XCTAssertEqual(request.auth, .none)
    }

    func test_givenEveryProvider_whenAuthorizeBuilt_thenPathMatchesRawValue() {
        // Boundary across the full enum: every case maps to its path segment.
        for provider in OAuthProvider.allCases {
            let request = Auth.authorize(provider: provider)
            XCTAssertEqual(request.path, "/api/auth/\(provider.rawValue)/authorize")
        }
    }

    // MARK: - authorize: link flag

    func test_givenLinkTrue_whenAuthorizeBuilt_thenAppendsLinkQuery() {
        // link=true records an account-link flow (verified: oauth_state carries
        // "link":true and GitHub gains the repo scope).
        let request = Auth.authorize(provider: .github, link: true)
        XCTAssertTrue(presentQuery(request).contains(QueryItem(name: "link", value: "true")))
    }

    func test_givenNoLink_whenAuthorizeBuilt_thenOmitsLinkQuery() {
        // Boundary: nil link is dropped by QueryItem's nil-skipping, leaving a
        // clean sign-in authorize URL with no query at all.
        let request = Auth.authorize(provider: .github)
        XCTAssertTrue(presentQuery(request).isEmpty)
    }

    // MARK: - authorize: mastodon instance

    func test_givenMastodonInstance_whenAuthorizeBuilt_thenAppendsInstanceQuery() {
        // Mastodon requires an instance hostname; without it the live server
        // 307s to /login?error=Instance domain is required.
        let request = Auth.authorize(provider: .mastodon, instance: "mastodon.social")
        XCTAssertEqual(request.path, "/api/auth/mastodon/authorize")
        XCTAssertTrue(presentQuery(request).contains(QueryItem(name: "instance", value: "mastodon.social")))
    }

    func test_givenLinkAndInstance_whenAuthorizeBuilt_thenAppendsBothQueries() {
        let request = Auth.authorize(provider: .mastodon, link: true, instance: "hachyderm.io")
        let present = presentQuery(request)
        XCTAssertTrue(present.contains(QueryItem(name: "link", value: "true")))
        XCTAssertTrue(present.contains(QueryItem(name: "instance", value: "hachyderm.io")))
        XCTAssertEqual(present.count, 2)
    }

    func test_givenEmptyInstanceString_whenAuthorizeBuilt_thenPassesEmptyThrough() {
        // Boundary: an empty-but-non-nil instance is NOT dropped (only nil is),
        // so the caller's whitespace/empty input reaches the server, which is
        // where the "Instance domain is required" rejection lives. The builder
        // is total and does not validate.
        let request = Auth.authorize(provider: .mastodon, instance: "")
        XCTAssertTrue(presentQuery(request).contains(QueryItem(name: "instance", value: "")))
    }

    // MARK: - linkedinStatus builder

    func test_givenLinkedinStatus_whenBuilt_thenTargetsStatusPathNoAuth() {
        let request = Auth.linkedinStatus()
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/auth/linkedin/status")
        XCTAssertEqual(request.auth, .none) // public 200 for anonymous callers
        XCTAssertNil(request.body)
        XCTAssertTrue(request.query.isEmpty)
    }

    // MARK: - LinkedInStatusResponse decode

    func test_givenConfiguredStatusJSON_whenDecoded_thenMapsConfiguredAndRedirect() throws {
        // Live fixture from the unauthenticated probe.
        let json = #"{"configured":true,"redirectUri":"https://interlinedlist.com/api/auth/linkedin/callback"}"#
        let decoded = try JSONCoders.makeDecoder().decode(LinkedInStatusResponse.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.configured)
        XCTAssertEqual(decoded.redirectUri, "https://interlinedlist.com/api/auth/linkedin/callback")
    }

    func test_givenUnconfiguredStatusJSON_whenDecoded_thenConfiguredIsFalse() throws {
        // Boundary: a not-configured deployment.
        let json = #"{"configured":false,"redirectUri":""}"#
        let decoded = try JSONCoders.makeDecoder().decode(LinkedInStatusResponse.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.configured)
        XCTAssertEqual(decoded.redirectUri, "")
    }

    func test_givenMissingConfiguredField_whenDecoded_thenThrows() throws {
        // Invalid input: a malformed/partial body must fail to decode rather
        // than silently defaulting.
        let json = #"{"redirectUri":"https://interlinedlist.com/api/auth/linkedin/callback"}"#
        XCTAssertThrowsError(
            try JSONCoders.makeDecoder().decode(LinkedInStatusResponse.self, from: Data(json.utf8))
        )
    }
}
