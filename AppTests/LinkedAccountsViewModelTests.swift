// LinkedAccountsViewModelTests
//
// BDD-named tests for the M6 Settings > Linked-accounts view model
// (browser-handoff OAuth linking). Quartet for load (happy / empty /
// failure) plus the link-URL resolution paths (happy / failure) and the
// `IdentityProvider.other` presentation fallback the pane renders.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class LinkedAccountsViewModelTests: XCTestCase {

    private func makeViewModel() -> (LinkedAccountsViewModel, StubUserService) {
        let user = StubUserService()
        let vm = LinkedAccountsViewModel(userService: user)
        return (vm, user)
    }

    private func identity(_ id: String, provider: IdentityProvider, handle: String?) -> LinkedIdentity {
        LinkedIdentity(id: id, provider: provider, handle: handle)
    }

    // MARK: - load

    func test_givenLinkedIdentities_whenLoading_thenRendersList() async {
        let (vm, user) = makeViewModel()
        user.enqueueIdentities(success: [
            identity("i1", provider: .github, handle: "ada"),
            identity("i2", provider: .mastodon, handle: "ada@m.social")
        ])

        await vm.load()

        XCTAssertEqual(vm.identities.map(\.id), ["i1", "i2"])
        XCTAssertNil(vm.loadError)
    }

    func test_givenNoIdentities_whenLoading_thenListIsEmpty() async {
        let (vm, user) = makeViewModel()
        user.enqueueIdentities(success: [])

        await vm.load()

        XCTAssertTrue(vm.identities.isEmpty)
        XCTAssertNil(vm.loadError)
    }

    func test_givenIdentitiesEndpointFails_whenLoading_thenSurfacesError() async {
        let (vm, user) = makeViewModel()
        user.enqueueIdentities(failure: TestError.upstream("session"))

        await vm.load()

        XCTAssertTrue(vm.identities.isEmpty)
        XCTAssertEqual(vm.loadError as? TestError, .upstream("session"))
    }

    // MARK: - linkURL

    func test_givenGitHubProvider_whenResolvingLinkURL_thenReturnsURL() {
        let (vm, _) = makeViewModel()

        let url = vm.linkURL(for: .github)

        XCTAssertEqual(url?.scheme, "https")
        XCTAssertTrue(url?.path.contains("/api/auth/github/authorize") ?? false)
        XCTAssertNil(vm.linkError)
    }

    func test_givenMastodonWithInstance_whenResolvingLinkURL_thenIncludesInstance() {
        let (vm, _) = makeViewModel()

        let url = vm.linkURL(for: .mastodon, instance: "mastodon.social")

        XCTAssertTrue(url?.absoluteString.contains("instance=mastodon.social") ?? false)
        XCTAssertNil(vm.linkError)
    }

    func test_givenLinkURLResolutionFails_whenResolvingLinkURL_thenReturnsNilAndSurfacesError() {
        let (vm, user) = makeViewModel()
        user.setLinkURLError(TestError.upstream("unsupported"))

        let url = vm.linkURL(for: .github)

        XCTAssertNil(url)
        XCTAssertEqual(vm.linkError as? TestError, .upstream("unsupported"))
    }

    // MARK: - presentation

    func test_givenKnownProviders_whenRendering_thenLabelsAndIconsResolve() {
        XCTAssertEqual(IdentityProvider.github.displayName, "GitHub")
        XCTAssertEqual(IdentityProvider.mastodon.displayName, "Mastodon")
        XCTAssertEqual(IdentityProvider.bluesky.displayName, "Bluesky")
        XCTAssertEqual(IdentityProvider.linkedin.displayName, "LinkedIn")
        XCTAssertFalse(IdentityProvider.github.iconName.isEmpty)
    }

    func test_givenOtherProvider_whenRendering_thenSurfacesRawTokenCapitalized() {
        XCTAssertEqual(IdentityProvider.other("threads").displayName, "Threads")
        XCTAssertEqual(IdentityProvider.other("").displayName, "Account")
        XCTAssertEqual(IdentityProvider.other("threads").iconName, "link")
    }

    func test_givenLinkableProviders_whenListing_thenExcludesOther() {
        let (vm, _) = makeViewModel()

        let providers = vm.linkableProviders

        XCTAssertEqual(providers, [.github, .mastodon, .bluesky, .linkedin])
    }
}
