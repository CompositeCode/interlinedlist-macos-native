// PreferencesViewModelTests
//
// BDD-named tests for the Settings ▸ Preferences view model (work-consolidation.md
// — settings storage): load, edit-detection, save (with the no-op and failure
// paths), driven by `StubUserService` so no networking is touched.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class PreferencesViewModelTests: XCTestCase {

    private func settings(
        defaultPubliclyVisible: Bool = true,
        showPreviews: Bool = true,
        showAdvancedPostSettings: Bool = false,
        isPrivateAccount: Bool = false,
        messagesPerPage: Int = 20
    ) -> UserSettings {
        UserSettings(
            defaultPubliclyVisible: defaultPubliclyVisible,
            showPreviews: showPreviews,
            showAdvancedPostSettings: showAdvancedPostSettings,
            isPrivateAccount: isPrivateAccount,
            messagesPerPage: messagesPerPage
        )
    }

    // MARK: - load

    func test_givenServerSettings_whenLoading_thenPopulatesWorkingCopyWithNoUnsavedChanges() async {
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(isPrivateAccount: true, messagesPerPage: 30))
        let viewModel = PreferencesViewModel(userService: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.settings.messagesPerPage, 30)
        XCTAssertTrue(viewModel.settings.isPrivateAccount)
        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertNil(viewModel.error)
    }

    func test_givenLoadFailure_whenLoading_thenSurfacesErrorAndKeepsDefault() async {
        let stub = StubUserService()
        stub.enqueueSettings(failure: URLError(.notConnectedToInternet))
        let viewModel = PreferencesViewModel(userService: stub)

        await viewModel.load()

        XCTAssertNotNil(viewModel.error)
        XCTAssertEqual(viewModel.settings, .default)
    }

    // MARK: - edit detection

    func test_givenLoadedSettings_whenEdited_thenHasChanges() async {
        let stub = StubUserService()
        stub.enqueueSettings(success: settings())
        let viewModel = PreferencesViewModel(userService: stub)
        await viewModel.load()

        viewModel.settings.showPreviews.toggle()

        XCTAssertTrue(viewModel.hasChanges)
    }

    // MARK: - save

    func test_givenChanges_whenSaving_thenPersistsSnapshotAndClearsChanges() async {
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(messagesPerPage: 20))
        let viewModel = PreferencesViewModel(userService: stub)
        await viewModel.load()
        viewModel.settings.messagesPerPage = 50
        stub.enqueueUpdateSettings(success: settings(messagesPerPage: 50))

        await viewModel.save()

        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertEqual(viewModel.settings.messagesPerPage, 50)
        XCTAssertEqual(stub.lastUpdatedSettings?.messagesPerPage, 50)
        XCTAssertNil(viewModel.error)
    }

    func test_givenNoChanges_whenSaving_thenDoesNotCallUpdate() async {
        let stub = StubUserService()
        stub.enqueueSettings(success: settings())
        let viewModel = PreferencesViewModel(userService: stub)
        await viewModel.load()

        await viewModel.save()

        XCTAssertFalse(stub.recorded.contains { $0.kind == .updateSettings })
    }

    func test_givenSaveFailure_whenSaving_thenSurfacesErrorAndKeepsChanges() async {
        let stub = StubUserService()
        stub.enqueueSettings(success: settings(messagesPerPage: 20))
        let viewModel = PreferencesViewModel(userService: stub)
        await viewModel.load()
        viewModel.settings.messagesPerPage = 40
        stub.enqueueUpdateSettings(failure: URLError(.timedOut))

        await viewModel.save()

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.hasChanges, "A failed save leaves the edits dirty so the user can retry")
    }
}
