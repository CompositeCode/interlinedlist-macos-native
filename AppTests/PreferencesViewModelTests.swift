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
        messagesPerPage: Int = 20,
        viewingPreference: ViewingPreference = .allMessages,
        notificationTrayLimit: Int = 20
    ) -> UserSettings {
        UserSettings(
            defaultPubliclyVisible: defaultPubliclyVisible,
            showPreviews: showPreviews,
            showAdvancedPostSettings: showAdvancedPostSettings,
            isPrivateAccount: isPrivateAccount,
            messagesPerPage: messagesPerPage,
            viewingPreference: viewingPreference,
            notificationTrayLimit: notificationTrayLimit
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
        viewModel.settings.messagesPerPage = 28
        stub.enqueueUpdateSettings(success: settings(messagesPerPage: 28))

        await viewModel.save()

        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertEqual(viewModel.settings.messagesPerPage, 28)
        XCTAssertEqual(stub.lastUpdatedSettings?.messagesPerPage, 28)
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
        viewModel.settings.messagesPerPage = 25
        stub.enqueueUpdateSettings(failure: URLError(.timedOut))

        await viewModel.save()

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.hasChanges, "A failed save leaves the edits dirty so the user can retry")
    }

    // MARK: - Cached-account invalidation
    //
    // A successful save re-resolves `CurrentUserStore` so preference-derived UI
    // elsewhere — today the composer's default visibility — reflects the change
    // without an app restart. Quartet: happy, no-op, upstream failure, and the
    // no-store boundary.

    func test_givenSaveSucceeds_whenSaving_thenRefreshesTheCachedAccount() async {
        // Given — the server will report the account now prefers private posts.
        let stub = StubUserService()
        stub.enqueueUpdateSettings(success: settings(defaultPubliclyVisible: false))
        let session = StubSessionManaging()
        let refreshed = MessageFixtures.currentUser(defaultPubliclyVisible: false)
        await session.enqueueRestore(success: .signedIn(refreshed))
        let store = CurrentUserStore(session: session)
        let viewModel = PreferencesViewModel(userService: stub, currentUserStore: store)
        viewModel.settings = settings(defaultPubliclyVisible: false)

        // When
        await viewModel.save()

        // Then — the cached account carries the new preference, so
        // `AppEnvironment.defaultComposeVisibility` now resolves to `.private`.
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(store.currentUser?.defaultPubliclyVisible, false)
        XCTAssertEqual(store.currentUser?.defaultVisibility, .private)
    }

    func test_givenNoChanges_whenSaving_thenDoesNotRefreshTheCachedAccount() async {
        // No-op: `save()` bails on `hasChanges`, so nothing should be re-read.
        let stub = StubUserService()
        let session = StubSessionManaging()
        await session.enqueueRestore(success: .signedIn(MessageFixtures.currentUser()))
        let store = CurrentUserStore(session: session)
        let viewModel = PreferencesViewModel(userService: stub, currentUserStore: store)

        await viewModel.save()

        XCTAssertNil(store.currentUser, "An unchanged pane must not re-resolve the account")
    }

    func test_givenSaveFailure_whenSaving_thenDoesNotRefreshTheCachedAccount() async {
        // Upstream failure: the write never landed, so refreshing the cache
        // would only re-read the *old* value and imply success.
        let stub = StubUserService()
        stub.enqueueUpdateSettings(failure: TestError.upstream("save failed"))
        let session = StubSessionManaging()
        await session.enqueueRestore(success: .signedIn(MessageFixtures.currentUser()))
        let store = CurrentUserStore(session: session)
        let viewModel = PreferencesViewModel(userService: stub, currentUserStore: store)
        viewModel.settings = settings(defaultPubliclyVisible: false)

        await viewModel.save()

        XCTAssertNotNil(viewModel.error)
        XCTAssertNil(store.currentUser, "A failed save must not re-resolve the account")
    }

    func test_givenNoCachedAccountStore_whenSaving_thenStillSucceeds() async {
        // Boundary: the store is optional, so previews and existing callers that
        // omit it must keep working.
        let stub = StubUserService()
        stub.enqueueUpdateSettings(success: settings(defaultPubliclyVisible: false))
        let viewModel = PreferencesViewModel(userService: stub)
        viewModel.settings = settings(defaultPubliclyVisible: false)

        await viewModel.save()

        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.settings.defaultPubliclyVisible)
    }
}
