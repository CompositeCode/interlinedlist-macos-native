import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `UserService` (PLAN.md §1 "Profile & account /
/// linked identities", "Organizations" / org switcher, §6 M6, §7 testing).
/// Quartet per public method: happy + invalid input + upstream API failure +
/// empty/boundary.
final class UserServiceTests: XCTestCase {

    // MARK: - identities

    func test_givenLinkedIdentities_whenLoading_thenMapsProvidersAndFields() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.identitiesEnvelope([
            Fixtures.linkedIdentityObject(id: "i-1", provider: "github", providerUsername: "ada"),
            Fixtures.linkedIdentityObject(id: "i-2", provider: "mastodon", providerUsername: "ada@m.social")
        ]))
        let service = UserService(api: api)

        // When
        let identities = try await service.identities()

        // Then — providers narrowed, URL strings parsed.
        XCTAssertEqual(identities.map(\.id), ["i-1", "i-2"])
        XCTAssertEqual(identities.first?.provider, .github)
        XCTAssertEqual(identities.first?.handle, "ada")
        XCTAssertEqual(identities.first?.profileURL?.absoluteString, "https://github.com/ada")
        XCTAssertEqual(identities.last?.provider, .mastodon)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/identities")
    }

    func test_givenMalformedIdentitiesEnvelope_whenLoading_thenThrowsDecoding() async throws {
        // Given — invalid input: missing `identities` key.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"oops":[]}"#)
        let service = UserService(api: api)

        // When / Then
        do {
            _ = try await service.identities()
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenIdentitiesEndpointFails_whenLoading_thenThrows() async throws {
        // Given — upstream API failure (session-only endpoint; e.g. 401).
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "session required"))
        let service = UserService(api: api)

        // When / Then
        do {
            _ = try await service.identities()
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "session required"))
        }
    }

    func test_givenNoIdentities_whenLoading_thenReturnsEmpty() async throws {
        // Given — boundary: account with no linked identities.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.identitiesEnvelope([]))
        let service = UserService(api: api)

        // When
        let identities = try await service.identities()

        // Then
        XCTAssertTrue(identities.isEmpty)
    }

    func test_givenUnknownProvider_whenLoading_thenPreservesOtherProvider() async throws {
        // Given — boundary: a provider the client doesn't type yet.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.identitiesEnvelope([
            Fixtures.linkedIdentityObject(id: "i-9", provider: "threads", providerUsername: "ada")
        ]))
        let service = UserService(api: api)

        // When
        let identities = try await service.identities()

        // Then — preserved under `.other`.
        XCTAssertEqual(identities.first?.provider, .other("threads"))
    }

    // MARK: - organizations

    func test_givenMemberships_whenLoadingOrganizations_thenMapsOrgAndRole() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.userOrganizationsEnvelope([
            Fixtures.userOrganizationObject(id: "o-1", name: "Acme", role: "owner"),
            Fixtures.userOrganizationObject(id: "o-2", name: "Globex", role: "member")
        ]))
        let service = UserService(api: api)

        // When
        let memberships = try await service.organizations()

        // Then
        XCTAssertEqual(memberships.map(\.id), ["o-1", "o-2"])
        XCTAssertEqual(memberships.first?.organization.name, "Acme")
        XCTAssertEqual(memberships.first?.role, .owner)
        XCTAssertEqual(memberships.first?.joinedAt, ISO8601DateFormatter().date(from: Fixtures.createdAtISO))
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/organizations")
    }

    func test_givenMalformedOrganizationsEnvelope_whenLoading_thenThrowsDecoding() async throws {
        // Given — invalid input: missing `organizations` key.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"orgs":[]}"#)
        let service = UserService(api: api)

        // When / Then
        do {
            _ = try await service.organizations()
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenOrganizationsEndpointFails_whenLoading_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = UserService(api: api)

        // When / Then
        do {
            _ = try await service.organizations()
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenNoMemberships_whenLoadingOrganizations_thenReturnsEmpty() async throws {
        // Given — boundary: user belongs to no orgs.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.userOrganizationsEnvelope([]))
        let service = UserService(api: api)

        // When
        let memberships = try await service.organizations()

        // Then
        XCTAssertTrue(memberships.isEmpty)
    }

    // MARK: - identityLinkURL

    func test_givenGitHubProvider_whenResolvingLinkURL_thenBuildsAuthorizeURLWithLinkTrue() throws {
        // Given — happy path: a typed provider against a stub origin.
        let api = StubAPIClient()
        let service = UserService(api: api, baseURL: URL(string: "https://example.test")!)

        // When
        let url = try service.identityLinkURL(provider: .github, instance: nil)

        // Then — path is the authorize route on our origin; link=true present.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.host, "example.test")
        XCTAssertEqual(components?.path, "/api/auth/github/authorize")
        XCTAssertEqual(
            components?.queryItems?.first { $0.name == "link" }?.value,
            "true"
        )
        // Bluesky / LinkedIn never need an instance, so none is sent.
        XCTAssertNil(components?.queryItems?.first { $0.name == "instance" })
    }

    func test_givenMastodonWithInstance_whenResolvingLinkURL_thenIncludesInstanceQuery() throws {
        // Given — Mastodon with a non-blank instance host.
        let api = StubAPIClient()
        let service = UserService(api: api, baseURL: URL(string: "https://example.test")!)

        // When
        let url = try service.identityLinkURL(provider: .mastodon, instance: "mastodon.social")

        // Then
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.path, "/api/auth/mastodon/authorize")
        XCTAssertEqual(
            components?.queryItems?.first { $0.name == "instance" }?.value,
            "mastodon.social"
        )
        XCTAssertEqual(
            components?.queryItems?.first { $0.name == "link" }?.value,
            "true"
        )
    }

    func test_givenOtherProvider_whenResolvingLinkURL_thenThrowsUnsupportedProvider() {
        // Given — invalid input: a provider the client doesn't type yet.
        let api = StubAPIClient()
        let service = UserService(api: api)

        // When / Then — rejected before any URL assembly.
        XCTAssertThrowsError(try service.identityLinkURL(provider: .other("threads"), instance: nil)) { error in
            XCTAssertEqual(error as? UserServiceError, .unsupportedProvider("threads"))
        }
    }

    func test_givenMastodonWithoutInstance_whenResolvingLinkURL_thenThrowsInstanceRequired() {
        // Given — boundary: Mastodon with a nil instance.
        let api = StubAPIClient()
        let service = UserService(api: api)

        // When / Then
        XCTAssertThrowsError(try service.identityLinkURL(provider: .mastodon, instance: nil)) { error in
            XCTAssertEqual(error as? UserServiceError, .mastodonInstanceRequired)
        }
    }

    func test_givenMastodonWithBlankInstance_whenResolvingLinkURL_thenThrowsInstanceRequired() {
        // Given — boundary: whitespace-only instance treated as absent.
        let api = StubAPIClient()
        let service = UserService(api: api)

        // When / Then
        XCTAssertThrowsError(try service.identityLinkURL(provider: .mastodon, instance: "   ")) { error in
            XCTAssertEqual(error as? UserServiceError, .mastodonInstanceRequired)
        }
    }
}
