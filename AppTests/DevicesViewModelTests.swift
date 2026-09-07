// DevicesViewModelTests
//
// BDD-named tests for Settings ▸ Devices (work-consolidation.md G17).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class DevicesViewModelTests: XCTestCase {

    private let thisMac = "dev-this"

    private func device(_ id: String, name: String? = nil, main: Bool = false) -> AppDevice {
        AppDevice(id: id, name: name ?? id, isMainWorkstation: main)
    }

    private func makeViewModel(_ stub: StubAppSettingsService?) -> DevicesViewModel {
        DevicesViewModel(service: stub, currentDeviceID: thisMac)
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

        // Exactly one main workstation may exist, so the old one must flip
        // locally without a second round-trip.
        XCTAssertEqual(stub.promotedIDs, ["new"])
        XCTAssertTrue(viewModel.devices.first { $0.id == "new" }!.isMainWorkstation)
        XCTAssertFalse(viewModel.devices.first { $0.id == "old" }!.isMainWorkstation)
    }

    func test_givenDevice_whenDeregistering_thenRemovesTheRow() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a"), device("b")])
        stub.enqueueDeregister()
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.deregister(device("a"))

        XCTAssertEqual(viewModel.devices.map(\.id), ["b"])
        XCTAssertEqual(stub.deregisteredIDs, ["a"])
    }

    // MARK: - Invalid input

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

    func test_givenNoAppKeyRegistered_whenLoading_thenReportsUnavailable() async {
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

    func test_givenDeregisterFailure_whenDeregistering_thenKeepsRowAndSurfacesError() async {
        let stub = StubAppSettingsService()
        stub.enqueueDevices(success: [device("a")])
        stub.enqueueDeregister(failure: URLError(.badServerResponse))
        let viewModel = makeViewModel(stub)
        await viewModel.load()

        await viewModel.deregister(device("a"))

        XCTAssertEqual(viewModel.devices.map(\.id), ["a"])
        XCTAssertNotNil(viewModel.error)
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
}
