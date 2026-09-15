// IntegrationsViewModelTests
//
// BDD quartet for Settings ▸ Integrations (GitHub #47 / G33).
//
// The cases that matter most are not about the pane — they are about the two
// live defects underneath it: Mastodon identities decoded as unknown providers,
// and the instance being dropped so unlink could address the wrong connection.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class IntegrationsViewModelTests: XCTestCase {

    private func identity(
        id: String,
        provider: IdentityProvider,
        instance: String? = nil,
        handle: String? = nil
    ) -> LinkedIdentity {
        LinkedIdentity(id: id, provider: provider, handle: handle, instance: instance)
    }

    // MARK: - Happy path

    func test_givenLinkedProviders_whenLoading_thenEveryRowArrives() async {
        let stub = StubUserService()
        stub.enqueueIdentities(success: [
            identity(id: "1", provider: .bluesky, handle: "a.bsky.social"),
            identity(id: "2", provider: .mastodon, instance: "techhub.social"),
            identity(id: "3", provider: .twitter, handle: "someone")
        ])
        stub.enqueueGitHubConnectionStatus(success: GitHubConnection(isConfigured: true))
        let viewModel = IntegrationsViewModel(user: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.connectedIdentities.count, 3)
        XCTAssertNil(viewModel.loadError)
        XCTAssertEqual(viewModel.github?.isConfigured, true)
    }

    func test_givenAVerifiableIdentity_whenVerifying_thenTheResultLandsOnThatRow() async {
        let stub = StubUserService()
        let bluesky = identity(id: "1", provider: .bluesky)
        stub.enqueueIdentities(success: [bluesky, identity(id: "2", provider: .linkedin)])
        stub.enqueueGitHubConnectionStatus(failure: TestError.upstream("no github"))
        stub.enqueueVerifyIdentity(success: true)
        let viewModel = IntegrationsViewModel(user: stub)
        await viewModel.load()

        await viewModel.verify(bluesky)

        XCTAssertEqual(viewModel.verifyResults["1"], true)
        XCTAssertNil(viewModel.verifyResults["2"], "a verify reports on its own row only")
    }

    // MARK: - Mastodon: the instance is the identity (the #47 defect)

    func test_givenSeveralMastodonInstances_whenDisconnectingOne_thenTheInstanceQualifiedTokenIsSent() async {
        // The defect this guards. The wire token is `mastodon:techhub.social`;
        // sending a bare `mastodon` on an account with two instances is
        // ambiguous enough that the server could disconnect the wrong one.
        let stub = StubUserService()
        let techhub = identity(id: "1", provider: .mastodon, instance: "techhub.social")
        let hachyderm = identity(id: "2", provider: .mastodon, instance: "hachyderm.io")
        stub.enqueueIdentities(success: [techhub, hachyderm])
        stub.enqueueGitHubConnectionStatus(failure: TestError.upstream("no github"))
        stub.enqueueUnlinkIdentity()
        let viewModel = IntegrationsViewModel(user: stub)
        await viewModel.load()

        await viewModel.disconnect(hachyderm)

        guard case .unlinkIdentity(let provider)? = stub.recorded.last?.kind else {
            return XCTFail("expected unlinkIdentity, got \(String(describing: stub.recorded.last))")
        }
        XCTAssertEqual(provider, "mastodon:hachyderm.io")
        XCTAssertEqual(viewModel.connectedIdentities.map(\.id), ["1"], "the other instance survives")
    }

    func test_givenMastodonAlreadyConnected_whenListingConnectable_thenItIsStillOffered() async {
        // Mastodon is the one provider that supports several connections, so it
        // must not disappear from the connect list once one instance is linked.
        let stub = StubUserService()
        stub.enqueueIdentities(success: [
            identity(id: "1", provider: .mastodon, instance: "techhub.social"),
            identity(id: "2", provider: .bluesky)
        ])
        stub.enqueueGitHubConnectionStatus(failure: TestError.upstream("no github"))
        let viewModel = IntegrationsViewModel(user: stub)
        await viewModel.load()

        XCTAssertTrue(viewModel.connectableProviders.contains(.mastodon))
        XCTAssertFalse(
            viewModel.connectableProviders.contains(.bluesky),
            "a single-connection provider disappears once it is linked"
        )
    }

    // MARK: - Upstream failure

    func test_givenAFailedVerify_whenVerifying_thenTheRowReportsTheErrorAndNotABrokenConnection() async {
        // A failed *request* is not a failed *connection*. Reporting "not
        // responding" when we simply could not ask would be a lie about the
        // provider.
        let stub = StubUserService()
        let bluesky = identity(id: "1", provider: .bluesky)
        stub.enqueueIdentities(success: [bluesky])
        stub.enqueueGitHubConnectionStatus(failure: TestError.upstream("no github"))
        stub.enqueueVerifyIdentity(failure: TestError.upstream("timeout"))
        let viewModel = IntegrationsViewModel(user: stub)
        await viewModel.load()

        await viewModel.verify(bluesky)

        XCTAssertNotNil(viewModel.rowErrors["1"])
        XCTAssertNil(viewModel.verifyResults["1"], "no verdict is recorded when the ask failed")
    }

    func test_givenAFailedDisconnect_whenDisconnecting_thenTheRowStays() async {
        // Not optimistic on purpose: a row that vanishes and comes back because
        // the write failed is worse than one that waits — the user needs to know
        // whether their cross-posting actually stopped.
        let stub = StubUserService()
        let bluesky = identity(id: "1", provider: .bluesky)
        stub.enqueueIdentities(success: [bluesky])
        stub.enqueueGitHubConnectionStatus(failure: TestError.upstream("no github"))
        stub.enqueueUnlinkIdentity(failure: TestError.upstream("nope"))
        let viewModel = IntegrationsViewModel(user: stub)
        await viewModel.load()

        await viewModel.disconnect(bluesky)

        XCTAssertEqual(viewModel.connectedIdentities.count, 1, "the connection is still there")
        XCTAssertNotNil(viewModel.rowErrors["1"])
    }

    func test_givenAFailedIdentitiesLoad_whenLoading_thenTheErrorIsSurfaced() async {
        let stub = StubUserService()
        stub.enqueueIdentities(failure: TestError.upstream("boom"))
        let viewModel = IntegrationsViewModel(user: stub)

        await viewModel.load()

        XCTAssertNotNil(viewModel.loadError)
        XCTAssertTrue(viewModel.connectedIdentities.isEmpty)
    }

    func test_givenAFailedGitHubStatus_whenLoading_thenTheRestOfThePaneStillWorks() async {
        // The GitHub status is a soft follow-up: only the GitHub row loses an
        // affordance, and the pane is otherwise fully usable.
        let stub = StubUserService()
        stub.enqueueIdentities(success: [identity(id: "1", provider: .bluesky)])
        stub.enqueueGitHubConnectionStatus(failure: TestError.upstream("nope"))
        let viewModel = IntegrationsViewModel(user: stub)

        await viewModel.load()

        XCTAssertNil(viewModel.github)
        XCTAssertNil(viewModel.loadError, "a soft failure is not a pane failure")
        XCTAssertEqual(viewModel.connectedIdentities.count, 1)
    }

    // MARK: - Boundary

    func test_givenNoConnections_whenLoading_thenEveryProviderIsOfferedAndNothingErrors() async {
        let stub = StubUserService()
        stub.enqueueIdentities(success: [])
        stub.enqueueGitHubConnectionStatus(success: GitHubConnection(isConfigured: true))
        let viewModel = IntegrationsViewModel(user: stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.connectedIdentities.isEmpty)
        XCTAssertEqual(viewModel.connectableProviders.count, 5)
        XCTAssertNil(viewModel.loadError)
    }

    func test_givenAnUnknownProvider_whenRendering_thenNoActionsAreOffered() async {
        // The client cannot describe what it would be verifying, or promise that
        // a disconnect addresses the right thing.
        XCTAssertFalse(IdentityProvider.other("carrier-pigeon").isVerifiable)
        XCTAssertFalse(IdentityProvider.other("carrier-pigeon").isDisconnectable)
        XCTAssertTrue(IdentityProvider.bluesky.isVerifiable)
    }

    func test_givenADisconnect_whenConfirming_thenTheConsequenceNamesWhatStops() async {
        // A generic "are you sure" tells the user nothing. The consequence
        // differs per provider, and it is the question.
        let stub = StubUserService()
        let viewModel = IntegrationsViewModel(user: stub)

        let github = viewModel.disconnectConsequence(for: identity(id: "1", provider: .github))
        XCTAssertTrue(github.contains("GitHub-backed lists"), github)

        let mastodon = viewModel.disconnectConsequence(
            for: identity(id: "2", provider: .mastodon, instance: "techhub.social")
        )
        XCTAssertTrue(mastodon.contains("techhub.social"), mastodon)
    }
}
