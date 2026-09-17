// ViewPreferencesParityTests
//
// BDD-named tests for the App-layer half of the View Preferences parity fix
// (work-consolidation.md G35 / issue #43):
//
//   • `PreferencesViewModel` — the corrected page-size range, the new Viewing
//     picker options, and the tray-limit control;
//   • `ComposerViewModel` — the gear that finally makes "Show advanced post
//     options" do something;
//   • `NotificationsListViewModel` — the tray limit reaching the service.
//
// View models only, against stubs — no SwiftUI rendering (per the skill's
// view-layer rule).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ViewPreferencesParityTests: XCTestCase {

    private func settings(
        showAdvancedPostSettings: Bool = false,
        messagesPerPage: Int = 20,
        viewingPreference: ViewingPreference = .allMessages,
        notificationTrayLimit: Int = 20
    ) -> UserSettings {
        UserSettings(
            defaultPubliclyVisible: true,
            showPreviews: true,
            showAdvancedPostSettings: showAdvancedPostSettings,
            isPrivateAccount: false,
            messagesPerPage: messagesPerPage,
            viewingPreference: viewingPreference,
            notificationTrayLimit: notificationTrayLimit
        )
    }

    // MARK: - Preferences pane: ranges

    func test_givenPreferencesPane_whenReadingControlRanges_thenMatchesTheWebsBounds() {
        // Happy path: the pane offers exactly what the web offers, so nothing
        // saved from macOS is unrepresentable there. It used to offer
        // `5...100 step 5`.
        let viewModel = PreferencesViewModel(userService: StubUserService())

        XCTAssertEqual(viewModel.messagesPerPageRange, 10...30)
        XCTAssertEqual(viewModel.notificationTrayLimitRange, 10...40)
    }

    func test_givenOutOfRangeStoredPageSize_whenLoading_thenClampsAndOpensClean() async {
        // Boundary: an account still holding a value the old macOS control
        // could save (5) must be corrected on load, not re-sent.
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(messagesPerPage: 5, notificationTrayLimit: 99))
        let viewModel = PreferencesViewModel(userService: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.settings.messagesPerPage, 10)
        XCTAssertEqual(viewModel.settings.notificationTrayLimit, 40)
        XCTAssertFalse(
            viewModel.hasChanges,
            "The clamp is applied to both the working copy and the baseline, so the pane opens clean"
        )
    }

    func test_givenTrayLimitEdit_whenSaving_thenSendsTheNewLimit() async {
        // Happy path for the new control: it round-trips like any other field.
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(notificationTrayLimit: 20))
        let viewModel = PreferencesViewModel(userService: stub)
        await viewModel.load()

        viewModel.settings.notificationTrayLimit = 35
        stub.enqueueUpdateSettings(success: settings(notificationTrayLimit: 35))
        await viewModel.save()

        XCTAssertNil(viewModel.error)
        XCTAssertEqual(stub.lastUpdatedSettings?.notificationTrayLimit, 35)
        XCTAssertEqual(viewModel.settings.notificationTrayLimit, 35)
    }

    // MARK: - Preferences pane: viewing preference

    func test_givenEachViewingPreference_whenSaved_thenRoundTripsThroughTheService() async {
        // The issue's happy-path case: all four values survive a save. The
        // account starts on a *different* value each time so `hasChanges` is
        // genuinely true — otherwise `save()` correctly short-circuits and the
        // assertion below would be testing nothing.
        for preference in ViewingPreference.selectable {
            let stub = StubUserService()
            stub.enqueueSettings(success: settings(viewingPreference: .other("unset")))
            let viewModel = PreferencesViewModel(userService: stub)
            await viewModel.load()

            viewModel.settings.viewingPreference = preference
            stub.enqueueUpdateSettings(success: settings(viewingPreference: preference))
            await viewModel.save()

            XCTAssertEqual(stub.lastUpdatedSettings?.viewingPreference, preference)
            XCTAssertEqual(viewModel.settings.viewingPreference, preference)
            XCTAssertNil(viewModel.error)
        }
    }

    func test_givenKnownViewingPreference_whenOfferingOptions_thenListsTheFourDocumentedValues() async {
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(viewingPreference: .followingOnly))
        let viewModel = PreferencesViewModel(userService: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.viewingPreferenceOptions, ViewingPreference.selectable)
    }

    func test_givenUnrecognisedViewingPreference_whenOfferingOptions_thenKeepsItSelectable() async {
        // Invalid input: a token this build doesn't know must still appear in
        // the picker. Dropping it would leave the control blank and let the
        // next unrelated save silently rewrite the account's preference.
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(viewingPreference: .other("mentions_only")))
        let viewModel = PreferencesViewModel(userService: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.viewingPreferenceOptions.count, 5)
        XCTAssertEqual(viewModel.viewingPreferenceOptions.last, .other("mentions_only"))
        XCTAssertTrue(
            viewModel.selectedViewingPreferenceIsServed,
            "An unknown filter falls back to the All feed, which the API does serve"
        )
    }

    func test_givenFollowerViewingPreference_whenSelected_thenPaneReportsTheFeedUnavailable() async {
        // Both follower feeds are backend-less (P1-G, re-verified 2026-09-09),
        // so the pane must say so rather than implying the filter is live.
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(viewingPreference: .followersOnly))
        let viewModel = PreferencesViewModel(userService: stub)
        await viewModel.load()

        XCTAssertFalse(viewModel.selectedViewingPreferenceIsServed)

        viewModel.settings.viewingPreference = .followingOnly
        XCTAssertFalse(viewModel.selectedViewingPreferenceIsServed)

        viewModel.settings.viewingPreference = .myMessages
        XCTAssertTrue(viewModel.selectedViewingPreferenceIsServed)
    }

    func test_givenViewingPreferenceSaveFails_whenSaving_thenSurfacesErrorAndKeepsTheEdit() async {
        // Upstream failure: the pane keeps the user's edit so they can retry,
        // and the working copy is not replaced by a value the server never took.
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(viewingPreference: .allMessages))
        let viewModel = PreferencesViewModel(userService: stub)
        await viewModel.load()

        viewModel.settings.viewingPreference = .myMessages
        stub.enqueueUpdateSettings(failure: URLError(.timedOut))
        await viewModel.save()

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.hasChanges)
        XCTAssertEqual(viewModel.settings.viewingPreference, .myMessages)
        XCTAssertEqual(viewModel.lastSaved.viewingPreference, .allMessages)
    }

    // MARK: - Composer gear (makes "Show advanced post options" real)

    func test_givenPreferenceOn_whenComposerOpens_thenAdvancedOptionsStartRevealed() {
        let viewModel = ComposerViewModel(
            messages: StubMessagesService(),
            eventBus: ComposerEventBus(),
            initialShowsAdvancedOptions: true
        )

        XCTAssertTrue(viewModel.showsAdvancedOptions)
    }

    func test_givenPreferenceOff_whenComposerOpens_thenAdvancedOptionsStartHidden() {
        // The bug this fixes: before G35 the preference was persisted and read
        // by the Preferences pane and by nothing else, so turning it off
        // changed nothing in the composer.
        let viewModel = ComposerViewModel(
            messages: StubMessagesService(),
            eventBus: ComposerEventBus(),
            initialShowsAdvancedOptions: false
        )

        XCTAssertFalse(viewModel.showsAdvancedOptions)
    }

    func test_givenGearTapped_whenToggling_thenRevealsOptionsAndPersistsThePreference() async {
        // Happy path, mirroring the web gear: flip the panel *and* PATCH the
        // single `showAdvancedPostSettings` key.
        let stub = StubUserService()
        stub.enqueueSetShowAdvancedPostSettings(success: settings(showAdvancedPostSettings: true))
        let viewModel = ComposerViewModel(
            messages: StubMessagesService(),
            eventBus: ComposerEventBus(),
            userService: stub,
            initialShowsAdvancedOptions: false
        )

        await viewModel.toggleAdvancedOptions()

        XCTAssertTrue(viewModel.showsAdvancedOptions)
        XCTAssertTrue(stub.recorded.contains { $0.kind == .setShowAdvancedPostSettings(enabled: true) })
        XCTAssertNil(viewModel.error)
    }

    func test_givenGearWriteFails_whenToggling_thenRollsBackAndSurfacesTheError() async {
        // Upstream failure + optimistic-UI rollback: the panel must not sit in
        // a state the account does not hold.
        let stub = StubUserService()
        stub.enqueueSetShowAdvancedPostSettings(failure: URLError(.notConnectedToInternet))
        let viewModel = ComposerViewModel(
            messages: StubMessagesService(),
            eventBus: ComposerEventBus(),
            userService: stub,
            initialShowsAdvancedOptions: true
        )

        await viewModel.toggleAdvancedOptions()

        XCTAssertTrue(viewModel.showsAdvancedOptions, "The optimistic hide must be rolled back")
        XCTAssertNotNil(viewModel.error)
    }

    func test_givenServerDisagrees_whenToggling_thenAdoptsTheServersAnswer() async {
        // The server is authoritative: if it refuses to flip the flag, the UI
        // follows it rather than the optimistic guess.
        let stub = StubUserService()
        stub.enqueueSetShowAdvancedPostSettings(success: settings(showAdvancedPostSettings: false))
        let viewModel = ComposerViewModel(
            messages: StubMessagesService(),
            eventBus: ComposerEventBus(),
            userService: stub,
            initialShowsAdvancedOptions: false
        )

        await viewModel.toggleAdvancedOptions()

        XCTAssertFalse(viewModel.showsAdvancedOptions)
    }

    func test_givenNoUserService_whenTogglingTheGear_thenStillFlipsLocally() async {
        // Boundary: previews and test hosts have no network seam wired; the
        // affordance must still work rather than appearing dead.
        let viewModel = ComposerViewModel(
            messages: StubMessagesService(),
            eventBus: ComposerEventBus(),
            initialShowsAdvancedOptions: false
        )

        await viewModel.toggleAdvancedOptions()

        XCTAssertTrue(viewModel.showsAdvancedOptions)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Notification tray limit reaches the service

    func test_givenTrayLimit_whenLoadingNotifications_thenPassesItToTheService() async {
        // The preference had no reader at all before this.
        let stub = StubNotificationsService()
        await stub.enqueueTray(success: NotificationTray(unreadCount: 0, items: []))
        let viewModel = NotificationsListViewModel(service: stub, trayLimit: 25)

        await viewModel.load()

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.first?.kind, .tray(limit: 25))
    }

    func test_givenNoTrayLimit_whenLoadingNotifications_thenLeavesThePageSizeToTheServer() async {
        // Boundary: the parameter is optional so existing callers are unchanged.
        let stub = StubNotificationsService()
        await stub.enqueueTray(success: NotificationTray(unreadCount: 0, items: []))
        let viewModel = NotificationsListViewModel(service: stub)

        await viewModel.load()

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.first?.kind, .tray(limit: nil))
    }
}
