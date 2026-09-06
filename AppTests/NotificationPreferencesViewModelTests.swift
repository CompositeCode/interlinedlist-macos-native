// NotificationPreferencesViewModelTests
//
// BDD-named tests for Settings ▸ Notifications (work-consolidation.md G18).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class NotificationPreferencesViewModelTests: XCTestCase {

    private func event(
        _ key: String,
        label: String? = nil,
        push: Bool? = true,
        inApp: Bool? = true,
        email: Bool? = nil
    ) -> NotificationEventPreference {
        NotificationEventPreference(
            key: key,
            label: label ?? key,
            channels: NotificationChannels(push: push, inApp: inApp, email: email)
        )
    }

    // MARK: - Happy path

    func test_givenCatalogue_whenLoading_thenPopulatesWithNoUnsavedChanges() async {
        let stub = StubNotificationPreferencesService()
        stub.enqueueCatalogue(success: [event("dig", label: "Digs")])
        let viewModel = NotificationPreferencesViewModel(service: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.events.map(\.key), ["dig"])
        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertNil(viewModel.error)
    }

    func test_givenChangedChannel_whenSaving_thenSendsOnlyTheChangedEvent() async {
        let stub = StubNotificationPreferencesService()
        stub.enqueueCatalogue(success: [event("dig"), event("follow")])
        stub.enqueueUpdate(success: [event("dig", push: false), event("follow")])
        let viewModel = NotificationPreferencesViewModel(service: stub)
        await viewModel.load()

        viewModel.setChannel("dig", .push, to: false)
        XCTAssertTrue(viewModel.hasChanges)
        await viewModel.save()

        // Only the edited event travels — a narrower PATCH is less likely to
        // clobber a change made on another device.
        XCTAssertEqual(stub.lastUpdatePayload.map(\.key), ["dig"])
        XCTAssertFalse(viewModel.hasChanges)
    }

    // MARK: - Invalid / unavailable

    func test_givenChannelTheServerOmitted_whenReading_thenReturnsNilSoTheSwitchIsHidden() async {
        let stub = StubNotificationPreferencesService()
        stub.enqueueCatalogue(success: [event("dig", email: nil)])
        let viewModel = NotificationPreferencesViewModel(service: stub)
        await viewModel.load()

        XCTAssertNil(viewModel.channelValue("dig", .email))
        XCTAssertEqual(viewModel.channelValue("dig", .push), true)
        XCTAssertNil(viewModel.channelValue("missing-event", .push))
    }

    func test_givenNoService_whenLoading_thenReportsUnavailable() async {
        let viewModel = NotificationPreferencesViewModel(service: nil)

        await viewModel.load()

        XCTAssertTrue(viewModel.isUnavailable)
        XCTAssertTrue(viewModel.events.isEmpty)
    }

    func test_givenNoChanges_whenSaving_thenDoesNotCallTheServer() async {
        let stub = StubNotificationPreferencesService()
        stub.enqueueCatalogue(success: [event("dig")])
        let viewModel = NotificationPreferencesViewModel(service: stub)
        await viewModel.load()

        await viewModel.save()

        XCTAssertTrue(stub.lastUpdatePayload.isEmpty, "an unchanged pane must not round-trip")
    }

    // MARK: - Upstream failure

    func test_givenSaveFailure_whenSaving_thenSurfacesErrorAndKeepsEdits() async {
        let stub = StubNotificationPreferencesService()
        stub.enqueueCatalogue(success: [event("dig")])
        stub.enqueueUpdate(failure: URLError(.timedOut))
        let viewModel = NotificationPreferencesViewModel(service: stub)
        await viewModel.load()
        viewModel.setChannel("dig", .push, to: false)

        await viewModel.save()

        XCTAssertNotNil(viewModel.error)
        // The user's edit must survive a failed save so they can retry.
        XCTAssertEqual(viewModel.channelValue("dig", .push), false)
        XCTAssertTrue(viewModel.hasChanges)
    }

    // MARK: - Empty / boundary

    func test_givenEmptyCatalogue_whenLoading_thenNoEventsAndNoError() async {
        let stub = StubNotificationPreferencesService()
        stub.enqueueCatalogue(success: [])
        let viewModel = NotificationPreferencesViewModel(service: stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertNil(viewModel.error)
    }
}
