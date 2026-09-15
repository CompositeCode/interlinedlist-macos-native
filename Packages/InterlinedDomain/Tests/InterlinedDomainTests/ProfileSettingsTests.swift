// ProfileSettingsTests
//
// The domain half of Settings ▸ Profile (GitHub #46 / G34).
//
// The two rules with real consequences are the change-gated PATCH body and the
// account-cap-versus-platform-ceiling reconciliation. Both are pinned against
// the live behaviour probed 2026-09-15 rather than against an assumption.

import XCTest
@testable import InterlinedDomain
@testable import InterlinedKit

final class ProfileSettingsTests: XCTestCase {

    /// The live account payload, captured 2026-09-15.
    private let userJSON = """
    {
      "id": "15e3d575-98bc-40e5-9aba-0d9cc9e30799",
      "email": "messenger@interlinedlist.com",
      "username": "messenger",
      "displayName": "Messenger & Recon @ InterlinedList",
      "avatar": "https://example.com/avatar.jpg",
      "bio": "Post it once, send it everywhere.",
      "theme": "light",
      "emailVerified": true,
      "maxMessageLength": 666,
      "defaultPubliclyVisible": false,
      "latitude": null,
      "longitude": null,
      "isPrivateAccount": false,
      "cleared": true,
      "accountStatus": "active",
      "customerStatus": "subscriber",
      "createdAt": "2026-03-23T23:23:59.755Z"
    }
    """

    private func settings(from json: String) throws -> ProfileSettings {
        let dto = try JSONCoders.makeDecoder().decode(UserDTO.self, from: Data(json.utf8))
        return ProfileSettings(from: dto)
    }

    // MARK: - Happy path

    func test_givenTheLiveAccountPayload_whenMapping_thenEveryProfileFieldArrives() throws {
        let settings = try settings(from: userJSON)

        XCTAssertEqual(settings.displayName, "Messenger & Recon @ InterlinedList")
        XCTAssertEqual(settings.bio, "Post it once, send it everywhere.")
        XCTAssertEqual(settings.theme, .light)
        XCTAssertEqual(settings.maxMessageLength, 666)
        XCTAssertEqual(settings.avatarURL?.absoluteString, "https://example.com/avatar.jpg")
        XCTAssertNil(settings.location, "this account publishes no location")
    }

    // MARK: - The change-gated body

    func test_givenOneChangedField_whenBuildingTheBody_thenOnlyThatFieldIsEncoded() throws {
        var edited = try settings(from: userJSON)
        let original = edited
        edited.bio = "Analytical engines"

        let data = try JSONCoders.makeEncoder().encode(edited.updateRequest(changedFrom: original))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["bio"] as? String, "Analytical engines")
        XCTAssertNil(json["displayName"], "an untouched field is absent from the body, not sent as itself")
        XCTAssertNil(json["theme"])
        XCTAssertNil(json["maxMessageLength"])
    }

    func test_givenNoChanges_whenBuildingTheBody_thenItIsEmpty() throws {
        let original = try settings(from: userJSON)

        let data = try JSONCoders.makeEncoder().encode(original.updateRequest(changedFrom: original))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertTrue(json.isEmpty)
        XCTAssertFalse(original.hasChanges(from: original))
    }

    // MARK: - Theme is unvalidated server-side

    func test_givenAnUnrecognisedTheme_whenMapping_thenItIsPreservedVerbatim() throws {
        // Probed live: `PATCH /api/user/update` accepted and stored "nonsense".
        // Collapsing an unknown value to `.system` here would mean the first
        // save of any other field silently rewrote the user's theme.
        let json = userJSON.replacingOccurrences(of: "\"theme\": \"light\"", with: "\"theme\": \"solarized\"")
        let settings = try self.settings(from: json)

        XCTAssertEqual(settings.theme, .unknown("solarized"))
        XCTAssertEqual(settings.theme.wireToken, "solarized", "and round-trips unchanged")
    }

    func test_givenTheThreeSelectableThemes_whenRoundTripping_thenTheirTokensMatchTheServers() {
        XCTAssertEqual(AppTheme.system.wireToken, "system")
        XCTAssertEqual(AppTheme.light.wireToken, "light")
        XCTAssertEqual(AppTheme.dark.wireToken, "dark")
        XCTAssertEqual(AppTheme(wireToken: "DARK"), .dark, "the server's casing is not load-bearing")
        XCTAssertFalse(
            AppTheme.selectable.contains(.unknown("solarized")),
            "an unknown value is one to preserve, never one to offer"
        )
    }

    // MARK: - Account cap versus platform ceiling

    func test_givenACapBelowTheCeiling_whenReconciling_thenTheAccountCapWins() {
        // The ordinary case: a user who deliberately lowered their own limit.
        XCTAssertEqual(ContentLimits.default.effectiveMessageLength(accountCap: 500), 500)
    }

    func test_givenACapAboveTheCeiling_whenReconciling_thenThePlatformWins() {
        // Reachable, not theoretical: the account field accepts up to 10000 and
        // the platform stops at 5000. Trusting the account value here would let
        // the composer accept a message the server then rejects.
        XCTAssertEqual(ContentLimits.default.effectiveMessageLength(accountCap: 9_000), 5_000)
    }

    func test_givenNoAccountCap_whenReconciling_thenThePlatformCeilingStandsAlone() {
        // `nil` means "not read", which is different from "the user chose no
        // cap" — substituting a default here would publish a guess.
        XCTAssertEqual(ContentLimits.default.effectiveMessageLength(accountCap: nil), 5_000)
    }

    // MARK: - Boundary — the cap's own range

    func test_givenAnOutOfRangeCap_whenSet_thenItIsClamped() {
        // The server answers `400 "maxMessageLength must be a positive integer
        // between 1 and 10000"`, so clamping is what stops a caller earning it.
        var settings = ProfileSettings()
        settings.maxMessageLength = 99_999
        XCTAssertEqual(settings.maxMessageLength, 10_000)
        settings.maxMessageLength = -5
        XCTAssertEqual(settings.maxMessageLength, 1)
        XCTAssertEqual(ProfileSettings(maxMessageLength: 0).maxMessageLength, 1)
    }

    // MARK: - Invalid input

    func test_givenAnOverLongBio_whenValidating_thenItIsRefusedBeforeTheCall() {
        var settings = ProfileSettings()
        settings.bio = String(repeating: "x", count: ProfileSettings.bioLengthLimit + 1)

        XCTAssertEqual(settings.validationError, .bioTooLong(limit: ProfileSettings.bioLengthLimit))
    }

    func test_givenAnEmptyDisplayName_whenValidating_thenItIsAccepted() {
        // The server falls back to the username. Rejecting it would invent a
        // rule the platform does not have.
        var settings = ProfileSettings()
        settings.displayName = ""

        XCTAssertNil(settings.validationError)
    }

    // MARK: - The location is read-only

    func test_givenAPublishedLocation_whenBuildingAnyUpdateBody_thenNoCoordinateIsEverSent() throws {
        // A location can be set through this API and cleared through nothing
        // (GitHub #91), so this client never writes one. The PATCH body has no
        // coordinate field at all — asserted rather than assumed, because the
        // failure mode is publishing a location the user cannot take back.
        let json = userJSON
            .replacingOccurrences(of: "\"latitude\": null", with: "\"latitude\": 47.6062")
            .replacingOccurrences(of: "\"longitude\": null", with: "\"longitude\": -122.3321")
        var edited = try settings(from: json)
        let original = edited
        XCTAssertEqual(edited.location?.latitude, 47.6062)

        edited.displayName = "Changed"
        let data = try JSONCoders.makeEncoder().encode(edited.updateRequest(changedFrom: original))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(body["latitude"])
        XCTAssertNil(body["longitude"])
    }
}
