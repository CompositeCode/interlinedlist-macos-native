import XCTest
import InterlinedDomain
@testable import InterlinedList

/// G21 — the app-wide reading-preferences store.
///
/// Exists because Settings ▸ Preferences shipped a "Show link previews" toggle
/// with no reader outside the Settings pane, so it had no effect on anything.
@MainActor
final class UserPreferencesStoreTests: XCTestCase {

    private func settings(showPreviews: Bool) -> UserSettings {
        var value = UserSettings.default
        value.showPreviews = showPreviews
        return value
    }

    // MARK: - Happy path

    /// GIVEN the server reports previews disabled
    /// WHEN the store refreshes
    /// THEN `showLinkPreviews` reflects it.
    func test_givenPreviewsDisabledOnServer_whenRefreshed_thenShowLinkPreviewsIsFalse() async {
        let service = StubUserService()
        service.enqueueSettings(success: settings(showPreviews: false))
        let store = UserPreferencesStore(userService: service)

        await store.refresh()

        XCTAssertFalse(store.showLinkPreviews)
    }

    // MARK: - Invalid / default state

    /// GIVEN no refresh has happened
    /// WHEN read
    /// THEN previews default to on, matching the server default — the timeline
    /// must not blank its cards while preferences are still loading.
    func test_givenNoRefresh_whenRead_thenDefaultsToShowingPreviews() {
        let store = UserPreferencesStore(userService: StubUserService())

        XCTAssertTrue(store.showLinkPreviews)
    }

    // MARK: - Upstream failure

    /// GIVEN the settings fetch fails
    /// WHEN the store refreshes
    /// THEN it keeps the defaults and does not propagate — preferences are a
    /// display nicety and must never break the timeline.
    func test_givenSettingsFetchFails_whenRefreshed_thenKeepsDefaultsSilently() async {
        let service = StubUserService()
        service.enqueueSettings(failure: URLError(.notConnectedToInternet))
        let store = UserPreferencesStore(userService: service)

        await store.refresh()

        XCTAssertTrue(store.showLinkPreviews)
    }

    // MARK: - Boundary

    /// GIVEN the Preferences pane saved a new value
    /// WHEN it writes through
    /// THEN the store adopts it immediately, so the timeline updates without
    /// waiting for a relaunch.
    func test_givenSavedSettings_whenAdopted_thenStoreReflectsThemImmediately() {
        let store = UserPreferencesStore(userService: StubUserService())
        XCTAssertTrue(store.showLinkPreviews)

        store.adopt(settings(showPreviews: false))

        XCTAssertFalse(store.showLinkPreviews)
    }

    /// The Preferences view model writes through to the store on save, which is
    /// what makes the toggle take effect live.
    func test_givenPreferencesSaved_whenViewModelSaves_thenStoreIsUpdated() async {
        let service = StubUserService()
        service.enqueueSettings(success: settings(showPreviews: true))
        service.enqueueUpdateSettings(success: settings(showPreviews: false))
        let store = UserPreferencesStore(userService: service)
        let viewModel = PreferencesViewModel(userService: service, preferencesStore: store)

        await viewModel.load()
        XCTAssertTrue(store.showLinkPreviews)

        viewModel.settings.showPreviews = false
        await viewModel.save()

        XCTAssertFalse(store.showLinkPreviews)
    }
}
