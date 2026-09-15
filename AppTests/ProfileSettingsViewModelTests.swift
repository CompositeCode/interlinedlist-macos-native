// ProfileSettingsViewModelTests
//
// BDD quartet for Settings ▸ Profile (GitHub #46 / G34).
//
// Two of these are about probe findings rather than about the view model, and
// they are the ones worth keeping: the theme field is unvalidated server-side,
// and the account's message cap can legally exceed the platform ceiling.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ProfileSettingsViewModelTests: XCTestCase {

    private func loaded(
        _ settings: ProfileSettings
    ) async -> (ProfileSettingsViewModel, StubUserService) {
        let stub = StubUserService()
        stub.enqueueProfileSettings(success: settings)
        let viewModel = ProfileSettingsViewModel(userService: stub)
        await viewModel.load()
        return (viewModel, stub)
    }

    // MARK: - Happy path

    func test_givenAnAccount_whenLoading_thenEveryFieldArrivesAndNothingLooksUnsaved() async {
        let (viewModel, _) = await loaded(
            ProfileSettings(displayName: "Ada", bio: "Maths", theme: .dark, maxMessageLength: 500)
        )

        XCTAssertEqual(viewModel.settings.displayName, "Ada")
        XCTAssertEqual(viewModel.settings.bio, "Maths")
        XCTAssertEqual(viewModel.settings.theme, .dark)
        XCTAssertEqual(viewModel.settings.maxMessageLength, 500)
        XCTAssertFalse(viewModel.hasChanges, "a fresh load has nothing to save")
        XCTAssertNil(viewModel.error)
    }

    func test_givenAnEditedField_whenSaving_thenOnlyThatFieldIsSent() async {
        // The point of the change-gated body: an untouched field must be absent
        // from the PATCH, or two windows open on the same account clobber each
        // other's edits.
        let original = ProfileSettings(displayName: "Ada", bio: "Maths", theme: .light, maxMessageLength: 666)
        let (viewModel, stub) = await loaded(original)
        var saved = original
        saved.bio = "Analytical engines"
        stub.enqueueUpdateProfileSettings(success: saved)

        viewModel.settings.bio = "Analytical engines"
        XCTAssertTrue(viewModel.hasChanges)
        await viewModel.save()

        let recorded = stub.recorded
        guard case .updateProfileSettings(let name, let bio, let theme, let cap)? = recorded.last?.kind else {
            return XCTFail("expected updateProfileSettings, got \(String(describing: recorded.last))")
        }
        XCTAssertEqual(bio, "Analytical engines")
        XCTAssertNil(name, "an untouched display name is not written")
        XCTAssertNil(theme, "an untouched theme is not written")
        XCTAssertNil(cap, "an untouched cap is not written")
        XCTAssertFalse(viewModel.hasChanges, "the save resets the baseline")
        XCTAssertEqual(viewModel.confirmation, "Saved.")
    }

    // MARK: - Invalid input — refused before the service is called

    func test_givenNoChanges_whenSaving_thenNoCallIsMade() async {
        let (viewModel, stub) = await loaded(ProfileSettings(displayName: "Ada"))

        await viewModel.save()

        let writes = stub.recorded.filter {
            if case .updateProfileSettings = $0.kind { return true } else { return false }
        }
        XCTAssertTrue(writes.isEmpty, "a no-op PATCH is still a write, and still bumps updatedAt")
    }

    func test_givenAnEmptyDisplayName_whenSaving_thenItIsAllowed() async {
        // Not a validation failure: the server falls back to the username, which
        // is exactly what /help/settings documents. Rejecting it would invent a
        // rule the platform does not have.
        let original = ProfileSettings(displayName: "Ada")
        let (viewModel, stub) = await loaded(original)
        stub.enqueueUpdateProfileSettings(success: ProfileSettings(displayName: ""))

        viewModel.settings.displayName = ""
        await viewModel.save()

        XCTAssertNil(viewModel.error)
        guard case .updateProfileSettings(let name, _, _, _)? = stub.recorded.last?.kind else {
            return XCTFail("expected updateProfileSettings")
        }
        XCTAssertEqual(name, "")
    }

    // MARK: - Upstream failure

    func test_givenASaveFailure_whenSaving_thenTheUsersTypingIsKept() async {
        // The one thing a failed save must not throw away.
        let (viewModel, stub) = await loaded(ProfileSettings(displayName: "Ada"))
        stub.enqueueUpdateProfileSettings(failure: TestError.upstream("nope"))

        viewModel.settings.displayName = "Ada Lovelace"
        await viewModel.save()

        XCTAssertNotNil(viewModel.error)
        XCTAssertEqual(viewModel.settings.displayName, "Ada Lovelace", "the edit survives the failure")
        XCTAssertTrue(viewModel.hasChanges, "and is still offered for saving")
    }

    func test_givenALoadFailure_whenLoading_thenTheErrorIsSurfaced() async {
        let stub = StubUserService()
        stub.enqueueProfileSettings(failure: TestError.upstream("boom"))
        let viewModel = ProfileSettingsViewModel(userService: stub)

        await viewModel.load()

        XCTAssertNotNil(viewModel.error)
        XCTAssertFalse(viewModel.hasChanges)
    }

    // MARK: - Boundary — the message cap against the platform ceiling

    func test_givenACapBelowThePlatformCeiling_whenComputing_thenTheAccountCapWins() async {
        let (viewModel, _) = await loaded(ProfileSettings(maxMessageLength: 500))

        XCTAssertEqual(viewModel.effectiveMessageLength, 500)
        XCTAssertFalse(viewModel.accountCapExceedsPlatform)
    }

    func test_givenACapAboveThePlatformCeiling_whenComputing_thenThePlatformWinsAndTheUserIsTold() async {
        // This is reachable, not theoretical: the account field accepts up to
        // 10000 and the platform stops at 5000. Honouring the account value here
        // would let the composer accept a message the server then rejects.
        let (viewModel, _) = await loaded(ProfileSettings(maxMessageLength: 9_000))

        XCTAssertEqual(viewModel.effectiveMessageLength, ContentLimits.default.messageMaxContentLength)
        XCTAssertTrue(viewModel.accountCapExceedsPlatform, "the pane says which number is really in force")
    }

    func test_givenAnOutOfRangeCap_whenSet_thenItIsClampedBeforeItCanReachTheServer() async {
        // The server rejects anything outside 1...10000 with a 400. Clamping in
        // the setter means no caller can earn that error.
        let (viewModel, _) = await loaded(ProfileSettings(maxMessageLength: 666))

        viewModel.settings.maxMessageLength = 99_999
        XCTAssertEqual(viewModel.settings.maxMessageLength, 10_000)

        viewModel.settings.maxMessageLength = 0
        XCTAssertEqual(viewModel.settings.maxMessageLength, 1)
    }

    // MARK: - Theme is unvalidated server-side

    func test_givenAnUnknownTheme_whenOfferingThePicker_thenTheAccountsOwnValueIsIncluded() async {
        // `PATCH /api/user/update` stored "nonsense" without complaint when
        // probed, so an unrecognised theme is a real state an account can be in.
        // Without offering it the Picker would have a selection matching no tag
        // — which SwiftUI renders as a blank control — and the first edit to any
        // other field would silently rewrite the value.
        let (viewModel, _) = await loaded(ProfileSettings(theme: .unknown("solarized")))

        XCTAssertEqual(viewModel.themeOptions.count, 4)
        XCTAssertTrue(viewModel.themeOptions.contains(.unknown("solarized")))
    }

    func test_givenAKnownTheme_whenOfferingThePicker_thenOnlyTheThreeAreOffered() async {
        let (viewModel, _) = await loaded(ProfileSettings(theme: .light))

        XCTAssertEqual(viewModel.themeOptions, AppTheme.selectable)
    }

    func test_givenAnUnknownTheme_whenSavingAnotherField_thenTheThemeIsNotRewritten() async {
        // The failure the picker option guards against, asserted at the wire.
        let original = ProfileSettings(bio: "Maths", theme: .unknown("solarized"))
        let (viewModel, stub) = await loaded(original)
        stub.enqueueUpdateProfileSettings(success: original)

        viewModel.settings.bio = "Analytical engines"
        await viewModel.save()

        guard case .updateProfileSettings(_, _, let theme, _)? = stub.recorded.last?.kind else {
            return XCTFail("expected updateProfileSettings")
        }
        XCTAssertNil(theme, "an untouched unknown theme is left exactly as the server holds it")
    }

    // MARK: - Avatar

    func test_givenAnAvatarURL_whenSet_thenItIsAppliedWithoutLookingLikeAnUnsavedEdit() async {
        // The avatar is written by its own route, outside the change-gated body.
        // If only the working copy were updated, Save would light up claiming an
        // unsaved change that does not exist.
        let (viewModel, stub) = await loaded(ProfileSettings(displayName: "Ada"))
        stub.enqueueSetAvatarFromURL(success: URL(string: "https://example.com/a.jpg"))

        viewModel.avatarURLInput = "https://example.com/a.jpg"
        await viewModel.setAvatarFromURL()

        XCTAssertEqual(viewModel.settings.avatarURL?.absoluteString, "https://example.com/a.jpg")
        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertEqual(viewModel.avatarURLInput, "", "the field clears on success")
    }

    func test_givenAnEmptyAvatarURL_whenSet_thenNoCallIsMade() async {
        let (viewModel, stub) = await loaded(ProfileSettings())

        viewModel.avatarURLInput = "   "
        await viewModel.setAvatarFromURL()

        let writes = stub.recorded.filter {
            if case .setAvatarFromURL = $0.kind { return true } else { return false }
        }
        XCTAssertTrue(writes.isEmpty)
    }

    // MARK: - Profile location is read-only (GitHub #57 / #91)

    func test_givenAPublishedLocation_whenLoading_thenItIsShownAndNeverSent() async {
        // A location can be set through the API and cleared through nothing, so
        // this client shows it and does not write it. Asserted at the wire: the
        // PATCH body has no location field to carry, and a save of other fields
        // must not smuggle one.
        let settings = ProfileSettings(
            displayName: "Ada",
            location: ProfileLocation(latitude: 47.6062, longitude: -122.3321)
        )
        let (viewModel, stub) = await loaded(settings)
        stub.enqueueUpdateProfileSettings(success: settings)

        XCTAssertEqual(viewModel.settings.location?.displayText, "47.6062, -122.3321")

        viewModel.settings.displayName = "Ada Lovelace"
        await viewModel.save()

        // `hasChanges` ignores location entirely — there is no way to edit it.
        XCTAssertFalse(viewModel.hasChanges)
    }

    func test_givenAHalfSetCoordinatePair_whenProjecting_thenThereIsNoLocation() async {
        // Rendering "47.6, —" would be worse than rendering nothing.
        XCTAssertNil(ProfileLocation(latitude: 47.6, longitude: nil))
        XCTAssertNil(ProfileLocation(latitude: nil, longitude: -122.3))
        XCTAssertNil(ProfileLocation(latitude: nil, longitude: nil))
    }
}
