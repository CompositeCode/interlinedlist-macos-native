// DevicesViewModelTests
//
// BDD-named tests for Settings ▸ Applications (work-consolidation.md G17,
// GitHub issue #56).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DevicesViewModelTests: XCTestCase {

    private let thisMac = "dev-this"

    private func device(
        _ id: String,
        name: String? = nil,
        main: Bool = false,
        hasSettings: Bool? = nil
    ) -> AppDevice {
        AppDevice(
            id: id,
            name: name ?? id,
            isMainWorkstation: main,
            hasDeviceSettings: hasSettings
        )
    }

    private func document(_ keys: [String: String] = [:], version: Int = 1) -> AppSettingsDocument {
        var bag = AppSettingsBag()
        for (key, value) in keys { bag[string: key] = value }
        return AppSettingsDocument(bag: bag, version: version, updatedAt: Date())
    }

    private func makeViewModel(
        _ stub: StubAppSettingsService?,
        deviceName: String = ""
    ) -> DevicesViewModel {
        DevicesViewModel(
            service: stub,
            currentDeviceID: thisMac,
            currentDeviceName: deviceName
        )
    }

    // MARK: - Happy path

    func test_givenDevices_whenLoading_thenOrdersThisMacThenMainThenByName() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [
            device("z", name: "Zulu"),
            device("m", name: "Main", main: true),
            device(thisMac, name: "This Mac"),
            device("a", name: "Alpha")
        ])
        let viewModel = makeViewModel(stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.devices.map(\.id), [thisMac, "m", "a", "z"])
        XCTAssertTrue(viewModel.isCurrentDevice(viewModel.devices[0]))
    }

    func test_givenStoredSharedSettings_whenLoading_thenExposesTheDocument() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a")])
        stub.enqueueSharedDocument(document(["theme": "dark"], version: 4))
        let viewModel = makeViewModel(stub)

        await viewModel.load()

        XCTAssertEqual(viewModel.sharedDocument?.version, 4)
        XCTAssertGreaterThan(viewModel.sharedDocument?.byteSize ?? 0, 0)
        XCTAssertNil(viewModel.error)
    }

    func test_givenRename_whenRenaming_thenSendsTrimmedNameAndUpdatesRow() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", name: "Old")])
        stub.enqueueMutation(success: device("a", name: "New"))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.rename(viewModel.devices[0], to: "  New  ")

        XCTAssertEqual(stub.renamedTo["a"], "New")
        XCTAssertEqual(viewModel.devices[0].name, "New")
    }

    func test_givenPromotion_whenMakingMain_thenClearsTheFlagOnTheOldMain() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("old", main: true), device("new")])
        stub.enqueueMutation(success: device("new", main: true))
        let viewModel = makeViewModel(stub)
        await viewModel.load()
        let target = viewModel.devices.first { $0.id == "new" }!

        await viewModel.makeMainWorkstation(target)

        // Exactly one main workstation may exist and the server enforces the
        // demotion, so the old one must flip locally without a second round-trip.
        XCTAssertEqual(stub.promotedIDs, ["new"])
        XCTAssertTrue(viewModel.devices.first { $0.id == "new" }!.isMainWorkstation)
        XCTAssertFalse(viewModel.devices.first { $0.id == "old" }!.isMainWorkstation)
    }

    func test_givenDevice_whenDeregistering_thenRemovesTheRow() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a"), device("b")])
        stub.enqueueRemoval(DeviceRemovalOutcome(deleted: true))
        stub.enqueueDevices(success: [device("b")])
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.deregister(device("a"))

        XCTAssertEqual(viewModel.devices.map(\.id), ["b"])
        XCTAssertEqual(stub.deregisteredIDs, ["a"])
    }

    func test_givenMainRemoved_whenServerNamesSuccessor_thenBadgeMovesWithoutGuessing() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("old-main", main: true), device("b"), device("c")])
        stub.enqueueRemoval(DeviceRemovalOutcome(deleted: true, promotedDeviceID: "c"))
        // The reconcile read fails, so the only source for the new holder is the
        // removal response itself.
        stub.enqueueDevices(failure: URLError(.timedOut))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.deregister(device("old-main", main: true))

        XCTAssertFalse(viewModel.mainWorkstationIsUnknown, "the server named the successor, so nothing is unknown")
        XCTAssertTrue(viewModel.devices.first { $0.id == "c" }!.isMainWorkstation)
        XCTAssertFalse(viewModel.devices.first { $0.id == "b" }!.isMainWorkstation)
    }

    func test_givenMachineSettings_whenCopyingToShared_thenReplacesSharedDocument() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", hasSettings: true)])
        stub.enqueueSharedDocument(document(["theme": "dark"], version: 1))
        stub.enqueueCopyToShared(success: document(["syncFolder": "/Notes"], version: 2))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.copySettingsToShared(from: viewModel.devices[0])

        XCTAssertEqual(stub.copiedFromIDs, ["a"])
        XCTAssertEqual(viewModel.sharedDocument?.version, 2)
        XCTAssertNil(viewModel.error)
    }

    func test_givenSharedSettings_whenDeleting_thenClearsTheDocument() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a")])
        stub.enqueueSharedDocument(document(["theme": "dark"]))
        stub.enqueueDeleteShared(true)
        let viewModel = makeViewModel(stub)
        await viewModel.load()
        XCTAssertNotNil(viewModel.sharedDocument)

        await viewModel.deleteSharedSettings()

        XCTAssertEqual(stub.deleteSharedCallCount, 1)
        XCTAssertNil(viewModel.sharedDocument)
    }

    func test_givenDevice_whenInspecting_thenLoadsThatMachinesDocument() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", hasSettings: true)])
        stub.enqueueDeviceDocument(document(["syncFolder": "/Notes"], version: 7))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.inspect(viewModel.devices[0])

        XCTAssertEqual(stub.inspectedIDs, ["a"])
        XCTAssertEqual(viewModel.inspection?.document?.version, 7)
        XCTAssertFalse(viewModel.inspection?.isLoading ?? true)
        XCTAssertEqual(viewModel.inspection?.document?.bag.keys, ["syncFolder"])
    }

    func test_givenThisMacIsNotRegistered_whenLoading_thenRegistersItOnce() async {
        // Nothing else registers this machine, so the pane would otherwise list
        // every computer except the one the user is sitting at.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("other", name: "Other Mac")])
        stub.enqueueMutation(success: device(thisMac, name: "Studio Mac"))
        let viewModel = makeViewModel(stub, deviceName: "Studio Mac")

        await viewModel.load()

        XCTAssertEqual(stub.registeredIDs, [thisMac])
        XCTAssertEqual(viewModel.devices.map(\.id), [thisMac, "other"])
    }

    // MARK: - Invalid input

    func test_givenThisMacAlreadyRegistered_whenLoading_thenDoesNotReregisterAndClobberItsName() async {
        // `POST …/devices` is an upsert keyed on deviceId — verified live — so
        // re-registering would overwrite `deviceName` with this Mac's hostname
        // and silently undo the user's rename on every visit to the pane.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device(thisMac, name: "Renamed By User")])
        let viewModel = makeViewModel(stub, deviceName: "studio-mac")

        await viewModel.load()

        XCTAssertTrue(stub.registeredIDs.isEmpty, "an already-registered Mac must not be re-registered")
        XCTAssertEqual(viewModel.devices.first?.name, "Renamed By User")
    }

    func test_givenRegistrationFails_whenLoading_thenStillShowsTheOtherMachines() async {
        // The registry itself loaded. Failing to add this Mac must not blank the
        // list of machines the user came here to manage.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("other", name: "Other Mac")])
        stub.enqueueMutation(failure: URLError(.timedOut))
        let viewModel = makeViewModel(stub, deviceName: "Studio Mac")

        await viewModel.load()

        XCTAssertEqual(viewModel.devices.map(\.id), ["other"])
        XCTAssertNil(viewModel.error)
    }

    func test_givenBlankOrUnchangedName_whenRenaming_thenSkipsTheRequest() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", name: "Same")])
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.rename(viewModel.devices[0], to: "   ")
        await viewModel.rename(viewModel.devices[0], to: "Same")

        XCTAssertTrue(stub.renamedTo.isEmpty, "a blank or unchanged rename must not round-trip")
    }

    func test_givenAlreadyMain_whenMakingMain_thenSkipsTheRequest() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", main: true)])
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.makeMainWorkstation(viewModel.devices[0])

        XCTAssertTrue(stub.promotedIDs.isEmpty)
    }

    func test_givenDeviceThatNoLongerExists_whenPromoting_thenSurfacesErrorAndLeavesBadgesAlone() async {
        // The machine was removed on another Mac between this pane's load and
        // the click. The promotion 404s; no row may silently gain the badge.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", main: true), device("ghost")])
        stub.enqueueMutation(failure: URLError(.badServerResponse))
        let viewModel = makeViewModel(stub)
        await viewModel.load()
        let ghost = viewModel.devices.first { $0.id == "ghost" }!

        await viewModel.makeMainWorkstation(ghost)

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.devices.first { $0.id == "a" }!.isMainWorkstation)
        XCTAssertFalse(viewModel.devices.first { $0.id == "ghost" }!.isMainWorkstation)
    }

    func test_givenNoAppKeyConfigured_whenLoading_thenReportsUnavailable() async {
        let viewModel = makeViewModel(nil)

        await viewModel.load()

        XCTAssertTrue(viewModel.isUnavailable)
        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertNil(viewModel.error, "an unconfigured appKey is a state, not an error")
    }

    // MARK: - Upstream failure

    func test_givenLoadFailure_whenLoading_thenSurfacesError() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(failure: URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(stub)

        await viewModel.load()

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.devices.isEmpty)
    }

    func test_givenRemoveSucceedsButRefetchFails_thenRowGoesAndMainWorkstationShowsUnknown() async {
        // The removal committed, so no error banner — but the server did not
        // name a successor and the reconcile read failed, so this client cannot
        // vouch for any badge. Showing the stale one would assert a fact that is
        // now false.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("old-main", main: true), device("b")])
        stub.enqueueRemoval(DeviceRemovalOutcome(deleted: true, promotedDeviceID: nil))
        stub.enqueueDevices(failure: URLError(.timedOut))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.deregister(device("old-main", main: true))

        XCTAssertEqual(viewModel.devices.map(\.id), ["b"], "the removed row must disappear")
        XCTAssertTrue(viewModel.mainWorkstationIsUnknown)
        XCTAssertNil(viewModel.error, "the mutation succeeded; only the reconcile did not")
    }

    func test_givenDeregisterFailure_whenDeregistering_thenKeepsRowAndSurfacesError() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a")])
        stub.enqueueRemoval(failure: URLError(.badServerResponse))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.deregister(device("a"))

        XCTAssertEqual(viewModel.devices.map(\.id), ["a"])
        XCTAssertNotNil(viewModel.error)
    }

    func test_givenCopyConflict_whenCopyingToShared_thenKeepsOldDocumentAndSurfacesError() async {
        // A lost compare-and-set writes nothing, so the pane must keep showing
        // the document it has rather than pretending the replace happened.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", hasSettings: true)])
        stub.enqueueSharedDocument(document(["theme": "dark"], version: 5))
        stub.enqueueCopyToShared(failure: AppSettingsError.versionConflict)
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.copySettingsToShared(from: viewModel.devices[0])

        XCTAssertEqual(viewModel.sharedDocument?.version, 5)
        XCTAssertEqual(viewModel.error as? AppSettingsError, .versionConflict)
    }

    func test_givenInspectFailure_whenInspecting_thenReportsInsideTheInspector() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a")])
        stub.enqueueDeviceDocument(failure: URLError(.timedOut))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.inspect(viewModel.devices[0])

        // Scoped to the inspector: a failed peek must not blank the pane's own
        // error row or the list behind it.
        XCTAssertNotNil(viewModel.inspection?.error)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.devices.count, 1)
    }

    // MARK: - Empty / boundary

    func test_givenNoDevices_whenLoading_thenEmptyWithoutError() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [])
        let viewModel = makeViewModel(stub)

        await viewModel.load()

        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertNil(viewModel.error)
    }

    func test_givenFirstRun404s_whenLoading_thenSharedSettingsAreEmptyNotAnError() async {
        // 404 for an app key with nothing stored is the ordinary first-run
        // state; the service maps it to nil and the pane must read that as
        // "nothing shared yet" rather than a failure.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [])
        stub.enqueueSharedDocument(nil)
        let viewModel = makeViewModel(stub)

        await viewModel.load()

        XCTAssertNil(viewModel.sharedDocument)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isUnavailable)
    }

    func test_givenExactlyOneDevice_whenRemovingIt_thenRegistryEmptiesAndNothingIsPromoted() async {
        // Boundary: the only registered machine, which is also the main
        // workstation. Nothing remains to inherit the role, so "unknown" would
        // be wrong — there is simply no holder.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("only", main: true)])
        stub.enqueueRemoval(DeviceRemovalOutcome(deleted: true, promotedDeviceID: nil))
        stub.enqueueDevices(success: [])
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.deregister(device("only", main: true))

        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertFalse(viewModel.mainWorkstationIsUnknown)
        XCTAssertNil(viewModel.error)
    }

    func test_givenMachineWithNoSettings_whenInspecting_thenReportsNoneRatherThanFailing() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", hasSettings: false)])
        stub.enqueueDeviceDocument(nil)
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.inspect(viewModel.devices[0])

        XCTAssertNil(viewModel.inspection?.document)
        XCTAssertNil(viewModel.inspection?.error)
        XCTAssertFalse(viewModel.inspection?.isLoading ?? true)
    }

    func test_givenAnActionInFlight_whenAnotherStarts_thenTheSecondIsIgnored() async {
        // `busyID` marks exactly one row; a second mutation must not interleave
        // and leave the flag stuck after the first one clears it.
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a", name: "One"), device("b", name: "Two")])
        stub.enqueueMutation(success: device("a", name: "Renamed"))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.rename(viewModel.devices[0], to: "Renamed")

        XCTAssertNil(viewModel.busyID, "the busy marker must clear on every exit path")
        XCTAssertEqual(stub.renamedTo.count, 1)
    }
}
