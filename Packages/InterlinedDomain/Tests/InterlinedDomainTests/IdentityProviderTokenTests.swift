// IdentityProviderTokenTests
//
// The provider-token parsing (GitHub #47 / G33).
//
// This is the file that matters in that issue. The live payload sends Mastodon
// **instance-qualified** — `"mastodon:techhub.social"` — and the client matched
// on `"mastodon"` exactly, so every Mastodon identity fell to `.other` and
// rendered as an unknown provider with none of its actions. X was missing from
// the enum entirely, despite the account having a linked X identity and
// cross-posting to X being a shipped feature.

import XCTest
@testable import InterlinedDomain
@testable import InterlinedKit

final class IdentityProviderTokenTests: XCTestCase {

    /// Captured from `GET /api/user/identities` on 2026-09-15 — all four
    /// identities the test account actually has.
    private let identitiesJSON = """
    {
      "identities": [
        {
          "id": "64ceab8b-a66e-40b8-8246-c2d20066366c",
          "provider": "bluesky",
          "providerUsername": "interlinedlist.bsky.social",
          "profileUrl": "https://bsky.app/profile/interlinedlist.bsky.social",
          "avatarUrl": null,
          "connectedAt": "2026-08-07T00:46:44.352Z",
          "lastVerifiedAt": "2026-09-05T04:00:20.264Z"
        },
        {
          "id": "dfbfcdb1-51a5-4523-902b-0ebfcfce4313",
          "provider": "mastodon:techhub.social",
          "providerUsername": "interlinedlist_crew@techhub.social",
          "profileUrl": "https://techhub.social/@interlinedlist_crew",
          "avatarUrl": "https://techhub.social/avatars/original/missing.png",
          "connectedAt": "2026-04-07T16:35:32.476Z",
          "lastVerifiedAt": "2026-08-22T06:00:41.130Z"
        },
        {
          "id": "da5c6ac1-8b5f-4a98-a791-afcdf7da1c75",
          "provider": "twitter",
          "providerUsername": "interlinedlist",
          "profileUrl": "https://twitter.com/interlinedlist",
          "avatarUrl": null,
          "connectedAt": "2026-08-07T00:47:00.159Z",
          "lastVerifiedAt": "2026-08-07T00:47:00.159Z"
        },
        {
          "id": "aaaaaaa1-0000-0000-0000-000000000000",
          "provider": "github",
          "providerUsername": "InterlinedListMessenger",
          "profileUrl": null,
          "avatarUrl": null,
          "connectedAt": "2026-08-07T00:47:00.159Z",
          "lastVerifiedAt": null
        }
      ]
    }
    """

    private func identities() throws -> [LinkedIdentity] {
        let response = try JSONCoders.makeDecoder().decode(
            IdentitiesResponse.self,
            from: Data(identitiesJSON.utf8)
        )
        return response.identities.map(LinkedIdentity.init(from:))
    }

    // MARK: - Happy path

    func test_givenTheCapturedIdentityList_whenMapping_thenEveryProviderIsRecognised() throws {
        let mapped = try identities()

        XCTAssertEqual(mapped.map(\.provider), [.bluesky, .mastodon, .twitter, .github])
        XCTAssertFalse(
            mapped.contains { if case .other = $0.provider { return true } else { return false } },
            "not one of the account's real identities should decode as unknown"
        )
    }

    func test_givenAnInstanceQualifiedToken_whenMapping_thenTheHostIsCarriedSeparately() throws {
        let mastodon = try XCTUnwrap(try identities().first { $0.provider == .mastodon })

        XCTAssertEqual(mastodon.instance, "techhub.social")
        XCTAssertEqual(
            mastodon.providerWireToken,
            "mastodon:techhub.social",
            "and the token round-trips, so unlink and verify address this instance"
        )
    }

    func test_givenANonMastodonIdentity_whenAskingForItsToken_thenItIsTheBareProvider() throws {
        let bluesky = try XCTUnwrap(try identities().first { $0.provider == .bluesky })

        XCTAssertNil(bluesky.instance)
        XCTAssertEqual(bluesky.providerWireToken, "bluesky")
    }

    // MARK: - Invalid input

    func test_givenAGenuinelyUnknownProvider_whenMapping_thenItIsPreservedNotGuessed() {
        // `.other` must keep working — the point of the fix is that Mastodon is
        // no longer *wrongly* in it, not that the case is gone.
        let provider = IdentityProvider(wireToken: "carrier-pigeon")
        XCTAssertEqual(provider, .other("carrier-pigeon"))
        XCTAssertEqual(provider.wireToken, "carrier-pigeon", "original casing survives")
    }

    func test_givenAMalformedInstanceToken_whenExtractingTheHost_thenThereIsNone() {
        // A trailing colon with no host is not an instance. Returning `""` would
        // produce a wire token of `"mastodon:"`, which addresses nothing.
        XCTAssertNil(IdentityProvider.instanceHost(fromWireToken: "mastodon:"))
        XCTAssertNil(IdentityProvider.instanceHost(fromWireToken: "mastodon"))
        XCTAssertNil(IdentityProvider.instanceHost(fromWireToken: "bluesky"))
        XCTAssertEqual(
            IdentityProvider.instanceHost(fromWireToken: "mastodon:a.b:c"),
            "a.b:c",
            "only the first colon separates; a host may legitimately contain more"
        )
    }

    func test_givenABareMastodonToken_whenMapping_thenItStillResolvesToMastodon() {
        // The server may not always qualify it. Handling only the qualified form
        // would trade one wrong answer for another.
        XCTAssertEqual(IdentityProvider(wireToken: "mastodon"), .mastodon)
        XCTAssertEqual(IdentityProvider(wireToken: "MASTODON:Techhub.Social"), .mastodon)
    }

    // MARK: - X / Twitter

    func test_givenEitherSpellingOfX_whenMapping_thenBothResolve() {
        XCTAssertEqual(IdentityProvider(wireToken: "twitter"), .twitter)
        XCTAssertEqual(IdentityProvider(wireToken: "x"), .twitter)
        XCTAssertEqual(IdentityProvider.twitter.wireToken, "twitter", "the wire still says twitter")
        XCTAssertEqual(IdentityProvider.twitter.displayName, "X", "the user still sees X")
    }

    // MARK: - Capability flags

    func test_givenEachProvider_whenAskingItsCapabilities_thenOnlyMastodonIsMultiInstance() {
        XCTAssertTrue(IdentityProvider.mastodon.supportsMultipleInstances)
        XCTAssertTrue(IdentityProvider.mastodon.requiresInstanceHost)
        for provider in [IdentityProvider.github, .bluesky, .linkedin, .twitter] {
            XCTAssertFalse(provider.supportsMultipleInstances, "\(provider)")
            XCTAssertFalse(provider.requiresInstanceHost, "\(provider)")
        }
    }

    func test_givenAnUnknownProvider_whenAskingItsCapabilities_thenNoActionsAreClaimed() {
        let unknown = IdentityProvider.other("carrier-pigeon")
        XCTAssertFalse(unknown.isVerifiable)
        XCTAssertFalse(unknown.isDisconnectable)
    }
}
