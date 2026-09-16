// SavedViewsViewModelTests
//
// BDD coverage for the saved-views control's view model
// (work-consolidation.md G40 / issue #81).
//
// Quartet per behavior: happy path, invalid input (which must NOT reach the
// service), upstream failure (which must roll the optimistic state back), and
// an empty/boundary case. Plus the event-bus routing pair — matching id
// mutates, non-matching id is a no-op — per the architecture checklist.
//
// No SwiftUI view is rendered here; `SavedViewsControl` is verified by build
// and by hand.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class SavedViewsViewModelTests: XCTestCase {

    private func makeViewModel(
        stub: StubListsService,
        eventBus: ListsEventBus = ListsEventBus()
    ) -> SavedViewsViewModel {
        SavedViewsViewModel(lists: stub, eventBus: eventBus, listId: "L1")
    }

    // MARK: - load

    func test_givenSharedAndPersonalViews_whenLoading_thenSplitsThemByScope() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1", name: "Team board", scope: .shared),
            ListsFixtures.savedView(id: "v-2", name: "Mine", scope: .personal)
        ])
        let viewModel = makeViewModel(stub: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.sharedViews.map(\.id), ["v-1"])
        XCTAssertEqual(viewModel.personalViews.map(\.id), ["v-2"])
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.first?.kind, .savedViews(listId: "L1"))
    }

    func test_givenAViewMarkedDefault_whenLoading_thenAppliesItOnOpen() async {
        // The acceptance criterion: `isDefault` is per user, so opening the list
        // must land on the arrangement *this* person chose — not the owner's.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1", name: "Owner's board", scope: .shared),
            ListsFixtures.savedView(id: "v-2", name: "Mine", density: .compact, isDefault: true)
        ])
        let viewModel = makeViewModel(stub: stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.selectedViewID, "v-2")
        XCTAssertEqual(viewModel.appliedDensity, .compact)
    }

    func test_givenNoDefaultView_whenLoading_thenAppliesNoneAndFallsBackToTheServerDensity() async {
        // Boundary: a list with views but no default opens on the plain list.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", density: .compact)])
        let viewModel = makeViewModel(stub: stub)

        await viewModel.load()

        XCTAssertNil(viewModel.selectedViewID)
        XCTAssertEqual(viewModel.appliedDensity, .comfortable)
    }

    func test_givenListWithNoViews_whenLoading_thenLeavesEverythingEmpty() async {
        // Boundary: the live `{"views":[]}` case.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [])
        let viewModel = makeViewModel(stub: stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.views.isEmpty)
        XCTAssertNil(viewModel.selectedViewID)
        XCTAssertNil(viewModel.error)
    }

    func test_givenUpstreamFailure_whenLoading_thenSurfacesTheError() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(failure: TestError.upstream("denied"))
        let viewModel = makeViewModel(stub: stub)

        await viewModel.load()

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.views.isEmpty)
    }

    // MARK: - select

    func test_givenLoadedViews_whenSelecting_thenAppliesWithoutCallingTheService() async {
        // Applying a view is a local read of data already loaded — it must not
        // cost a round-trip, so it keeps working offline.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", density: .compact)])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        viewModel.select(viewID: "v-1")

        XCTAssertEqual(viewModel.selectedViewID, "v-1")
        XCTAssertEqual(viewModel.appliedDensity, .compact)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1, "Selecting must not issue a second call")
    }

    func test_givenUnknownViewID_whenSelecting_thenKeepsTheCurrentSelection() async {
        // Invalid input: an id that is not loaded must not blank the picker.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", isDefault: true)])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        viewModel.select(viewID: "ghost")

        XCTAssertEqual(viewModel.selectedViewID, "v-1")
    }

    // MARK: - create

    func test_givenNameAndScope_whenCreating_thenCallsServiceAndAppliesTheNewView() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [])
        await stub.enqueueCreateSavedView(success: ListsFixtures.savedView(id: "v-9", name: "Reading", scope: .shared))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.create(name: "Reading", scope: .shared, makeDefault: false)

        XCTAssertEqual(viewModel.views.map(\.id), ["v-9"])
        XCTAssertEqual(viewModel.selectedViewID, "v-9")
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        XCTAssertEqual(
            recorded.last?.kind,
            .createSavedView(listId: "L1", name: "Reading", scope: .shared, isDefault: false)
        )
    }

    func test_givenBlankName_whenCreating_thenReportsValidationAndCallsNoService() async {
        // Invalid input. The API accepts "" happily, so nothing downstream
        // catches this — an unnamed row in the picker is indistinguishable from
        // the next one.
        let stub = StubListsService()
        let viewModel = makeViewModel(stub: stub)

        await viewModel.create(name: "   ", scope: .personal, makeDefault: false)

        XCTAssertNotNil(viewModel.validationMessage)
        XCTAssertTrue(viewModel.views.isEmpty)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty, "A blank name must not reach the service")
    }

    func test_givenNewDefaultView_whenCreating_thenDemotesThePreviousDefault() async {
        // Boundary on the single-default rule: the server clears the old
        // default, so two windows must not end up each showing one.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", isDefault: true)])
        await stub.enqueueCreateSavedView(success: ListsFixtures.savedView(id: "v-2", isDefault: true))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.create(name: "Newer", scope: .personal, makeDefault: true)

        XCTAssertEqual(viewModel.views.filter(\.isDefault).map(\.id), ["v-2"])
    }

    func test_givenUpstreamFailure_whenCreating_thenSurfacesTheErrorAndAddsNothing() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [])
        await stub.enqueueCreateSavedView(failure: TestError.upstream("bad scope"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.create(name: "Reading", scope: .shared, makeDefault: false)

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.views.isEmpty)
        XCTAssertNil(viewModel.selectedViewID)
    }

    // MARK: - rename

    func test_givenLoadedView_whenRenaming_thenSwapsTheLabelAndKeepsTheConfigUntouched() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", name: "Old")])
        await stub.enqueueUpdateSavedView(success: ListsFixtures.savedView(id: "v-1", name: "New"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.rename(viewID: "v-1", to: "New")

        XCTAssertEqual(viewModel.views.first?.name, "New")
        // A rename must send NO config: `PUT` replaces the stored object whole,
        // so a partial one would silently reset whatever it omitted.
        let recorded = await stub.recorded
        XCTAssertEqual(
            recorded.last?.kind,
            .updateSavedView(listId: "L1", viewId: "v-1", name: "New", hasConfig: false, isDefault: nil)
        )
    }

    func test_givenBlankRename_whenRenaming_thenReportsValidationAndCallsNoService() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", name: "Old")])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.rename(viewID: "v-1", to: " ")

        XCTAssertNotNil(viewModel.validationMessage)
        XCTAssertEqual(viewModel.views.first?.name, "Old")
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1, "Only the load should have reached the service")
    }

    func test_givenUpstreamFailure_whenRenaming_thenRestoresTheOriginalName() async {
        // Optimistic-UI rollback.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", name: "Old")])
        await stub.enqueueUpdateSavedView(failure: TestError.upstream("forbidden"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.rename(viewID: "v-1", to: "New")

        XCTAssertEqual(viewModel.views.first?.name, "Old")
        XCTAssertNotNil(viewModel.error)
    }

    func test_givenUnknownViewID_whenRenaming_thenDoesNothing() async {
        // Boundary: renaming a row that is not loaded.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.rename(viewID: "ghost", to: "New")

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    // MARK: - makeDefault

    func test_givenSecondView_whenMakingItDefault_thenExactlyOneViewIsDefault() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1", isDefault: true),
            ListsFixtures.savedView(id: "v-2")
        ])
        await stub.enqueueUpdateSavedView(success: ListsFixtures.savedView(id: "v-2", isDefault: true))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.makeDefault(viewID: "v-2")

        XCTAssertEqual(viewModel.views.filter(\.isDefault).map(\.id), ["v-2"])
        let recorded = await stub.recorded
        XCTAssertEqual(
            recorded.last?.kind,
            .updateSavedView(listId: "L1", viewId: "v-2", name: nil, hasConfig: false, isDefault: true)
        )
    }

    func test_givenUpstreamFailure_whenMakingDefault_thenRestoresThePreviousDefault() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1", isDefault: true),
            ListsFixtures.savedView(id: "v-2")
        ])
        await stub.enqueueUpdateSavedView(failure: TestError.upstream("nope"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.makeDefault(viewID: "v-2")

        XCTAssertEqual(viewModel.views.filter(\.isDefault).map(\.id), ["v-1"])
        XCTAssertNotNil(viewModel.error)
    }

    func test_givenUnknownViewID_whenMakingDefault_thenCallsNoService() async {
        // Invalid input.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.makeDefault(viewID: "ghost")

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    // MARK: - setDensity

    func test_givenAppliedView_whenChangingDensity_thenSendsTheWholeConfig() async {
        // `PUT` replaces the config object, so the write must carry the
        // unconfirmed `filters` / `search` through untouched — dropping them
        // would delete arrangement the web may have set.
        let stub = StubListsService()
        let filters: [ListCellValue] = [.object(["key": .string("read")])]
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1", filters: filters, search: "bikes", isDefault: true)
        ])
        await stub.enqueueUpdateSavedView(
            success: ListsFixtures.savedView(id: "v-1", density: .compact, filters: filters, search: "bikes", isDefault: true)
        )
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.setDensity(.compact)

        XCTAssertEqual(viewModel.appliedDensity, .compact)
        let sentConfig = await stub.lastUpdatedSavedViewConfig
        XCTAssertEqual(sentConfig?.density, .compact)
        XCTAssertEqual(sentConfig?.mode, .records)
        XCTAssertEqual(sentConfig?.filters, filters)
        XCTAssertEqual(sentConfig?.search, "bikes")
    }

    func test_givenNoAppliedView_whenChangingDensity_thenCallsNoService() async {
        // Invalid input: there is no view to store the change in.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1")])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.setDensity(.compact)

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenTheSameDensity_whenChangingDensity_thenSkipsTheRoundTrip() async {
        // Boundary: a no-op change must not spend a write.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1", density: .comfortable, isDefault: true)
        ])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.setDensity(.comfortable)

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenUpstreamFailure_whenChangingDensity_thenRollsBack() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1", density: .comfortable, isDefault: true)
        ])
        await stub.enqueueUpdateSavedView(failure: TestError.upstream("nope"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.setDensity(.compact)

        XCTAssertEqual(viewModel.appliedDensity, .comfortable)
        XCTAssertNotNil(viewModel.error)
    }

    // MARK: - delete

    func test_givenLoadedView_whenDeleting_thenRemovesItAndClearsTheSelection() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", isDefault: true)])
        await stub.enqueueDeleteSavedViewSuccess()
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.delete(viewID: "v-1")

        XCTAssertTrue(viewModel.views.isEmpty)
        XCTAssertNil(viewModel.selectedViewID)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.last?.kind, .deleteSavedView(listId: "L1", viewId: "v-1"))
    }

    func test_givenUpstreamFailure_whenDeleting_thenRestoresTheRowAndTheSelection() async {
        // Optimistic-UI rollback, including the applied selection.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", isDefault: true)])
        await stub.enqueueDeleteSavedView(failure: TestError.upstream("forbidden"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.delete(viewID: "v-1")

        XCTAssertEqual(viewModel.views.map(\.id), ["v-1"])
        XCTAssertEqual(viewModel.selectedViewID, "v-1")
        XCTAssertNotNil(viewModel.error)
    }

    func test_givenUnknownViewID_whenDeleting_thenCallsNoService() async {
        // Invalid input.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.delete(viewID: "ghost")

        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    // MARK: - fork

    func test_givenSharedView_whenForking_thenAppendsAPersonalCopyAndAppliesIt() async {
        // The escape hatch: a collaborator takes the owner's arrangement rather
        // than being stuck with it.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1", name: "Owner's board", scope: .shared)
        ])
        await stub.enqueueForkSavedView(
            success: ListsFixtures.savedView(id: "v-9", name: "Owner's board copy", scope: .personal)
        )
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.fork(viewID: "v-1", name: "Owner's board copy")

        XCTAssertEqual(viewModel.personalViews.map(\.id), ["v-9"])
        XCTAssertEqual(viewModel.selectedViewID, "v-9")
        let recorded = await stub.recorded
        XCTAssertEqual(
            recorded.last?.kind,
            .forkSavedView(listId: "L1", viewId: "v-1", name: "Owner's board copy")
        )
    }

    func test_givenBlankForkName_whenForking_thenReportsValidationAndCallsNoService() async {
        // Invalid input: a *supplied* blank name is a mistake; a nil one is
        // legal and lets the server pick.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", scope: .shared)])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.fork(viewID: "v-1", name: "  ")

        XCTAssertNotNil(viewModel.validationMessage)
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenNoForkName_whenForking_thenLetsTheServerName() async {
        // Boundary.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", scope: .shared)])
        await stub.enqueueForkSavedView(success: ListsFixtures.savedView(id: "v-9", name: "Copy of board"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.fork(viewID: "v-1", name: nil)

        XCTAssertEqual(viewModel.views.map(\.id), ["v-1", "v-9"])
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.last?.kind, .forkSavedView(listId: "L1", viewId: "v-1", name: nil))
    }

    func test_givenUpstreamFailure_whenForking_thenAddsNothing() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", scope: .shared)])
        await stub.enqueueForkSavedView(failure: TestError.upstream("nope"))
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        await viewModel.fork(viewID: "v-1", name: "Copy")

        XCTAssertEqual(viewModel.views.map(\.id), ["v-1"])
        XCTAssertNotNil(viewModel.error)
    }

    // MARK: - Event-bus routing

    func test_givenSavedViewsChangedForThisList_whenApplying_thenReplacesTheCollection() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1")])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        viewModel.apply(event: .savedViewsChanged(
            listId: "L1",
            views: [ListsFixtures.savedView(id: "v-2", isDefault: true)]
        ))

        XCTAssertEqual(viewModel.views.map(\.id), ["v-2"])
        // The applied view was deleted in the other window, so fall back to the
        // new default rather than leaving a dangling selection.
        XCTAssertEqual(viewModel.selectedViewID, "v-2")
    }

    func test_givenSavedViewsChangedForAnotherList_whenApplying_thenIsANoOp() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1")])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        viewModel.apply(event: .savedViewsChanged(listId: "OTHER", views: []))

        XCTAssertEqual(viewModel.views.map(\.id), ["v-1"])
    }

    func test_givenTheAppliedViewSurvives_whenApplyingAnUpdate_thenKeepsTheSelection() async {
        // Boundary: another window renamed a *different* view; the selection
        // here must not jump.
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [
            ListsFixtures.savedView(id: "v-1"),
            ListsFixtures.savedView(id: "v-2", isDefault: true)
        ])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()
        viewModel.select(viewID: "v-1")

        viewModel.apply(event: .savedViewsChanged(listId: "L1", views: [
            ListsFixtures.savedView(id: "v-1"),
            ListsFixtures.savedView(id: "v-2", name: "Renamed elsewhere", isDefault: true)
        ]))

        XCTAssertEqual(viewModel.selectedViewID, "v-1")
        XCTAssertEqual(viewModel.views.last?.name, "Renamed elsewhere")
    }

    func test_givenListDeleted_whenApplying_thenClearsEverything() async {
        let stub = StubListsService()
        await stub.enqueueSavedViews(success: [ListsFixtures.savedView(id: "v-1", isDefault: true)])
        let viewModel = makeViewModel(stub: stub)
        await viewModel.load()

        viewModel.apply(event: .listDeleted(id: "L1"))

        XCTAssertTrue(viewModel.views.isEmpty)
        XCTAssertNil(viewModel.selectedViewID)
    }
}
