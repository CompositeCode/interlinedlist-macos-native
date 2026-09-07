import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD coverage for `AppSettingsService`, `AppSettingsBag` and the device
/// registry (work-consolidation.md G17).
final class AppSettingsServiceTests: XCTestCase {

    private let appKey = "interlinedlist-macos"

    private func makeService(_ api: StubAPIClient) -> AppSettingsService {
        AppSettingsService(api: api, appKey: appKey)
    }

    // MARK: - Happy path

    func test_givenBootstrapBody_whenLaunching_thenSplitsSharedAndDeviceSettings() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "shared": { "theme": "dark", "postsPerPage": 25 },
          "device": { "syncFolder": "/Users/x/Notes" },
          "isNewDevice": true, "seededFromMainWorkstation": true }
        """#)
        let service = makeService(api)

        let snapshot = try await service.bootstrap(deviceID: "dev-1")

        XCTAssertEqual(snapshot.shared[string: "theme"], "dark")
        XCTAssertEqual(snapshot.shared[int: "postsPerPage"], 25)
        XCTAssertEqual(snapshot.device[string: "syncFolder"], "/Users/x/Notes")
        XCTAssertTrue(snapshot.isNewDevice)
        XCTAssertTrue(snapshot.seededFromMainWorkstation)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/app-settings/interlinedlist-macos/bootstrap")
        XCTAssertEqual(recorded.first?.query["deviceId"], "dev-1")
    }

    func test_givenDevices_whenListing_thenMapsRegistry() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "devices": [ { "deviceId": "dev-1", "name": "Studio Mac", "isMainWorkstation": true },
                       { "deviceId": "dev-2" } ] }
        """#)
        let service = makeService(api)

        let devices = try await service.devices()

        XCTAssertEqual(devices.map(\.id), ["dev-1", "dev-2"])
        XCTAssertTrue(devices[0].isMainWorkstation)
        // An unnamed device falls back to its id so a row is never blank.
        XCTAssertEqual(devices[1].name, "dev-2")
        XCTAssertFalse(devices[1].isMainWorkstation)
    }

    func test_givenPromotion_whenMakingMainWorkstation_thenSendsOnlyTheFlag() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "deviceId": "dev-2", "isMainWorkstation": true }"#)
        let service = makeService(api)

        let device = try await service.makeMainWorkstation(deviceID: "dev-2")

        XCTAssertTrue(device.isMainWorkstation)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
        XCTAssertEqual(recorded.first?.path, "/api/user/app-settings/interlinedlist-macos/devices/dev-2")
    }

    func test_givenDeviceID_whenDeregistering_thenSendsDelete() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = makeService(api)

        try await service.deregisterDevice(deviceID: "dev-2")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
    }

    // MARK: - Invalid / forward-compatibility
    //
    // The behaviour that matters most for synced settings: an older build must
    // not delete keys written by a newer one.

    func test_givenUnknownKeys_whenEditingAndWritingBack_thenUnknownKeysSurvive() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "settings": { "theme": "dark", "futureFeature": { "nested": true } } }
        """#)
        await api.enqueue(json: #"""
        { "settings": { "theme": "light", "futureFeature": { "nested": true } } }
        """#)
        let service = makeService(api)

        var bag = try await service.sharedSettings()
        XCTAssertEqual(bag[string: "theme"], "dark")
        bag[string: "theme"] = "light"

        let saved = try await service.writeSharedSettings(bag)

        XCTAssertEqual(saved[string: "theme"], "light")
        XCTAssertTrue(saved.keys.contains("futureFeature"),
                      "a key this build does not understand must survive a save")
    }

    func test_givenWrongTypeOrMissingKey_whenReading_thenReturnsNilRatherThanTrapping() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "settings": { "postsPerPage": "twenty-five" } }"#)
        let service = makeService(api)

        let bag = try await service.sharedSettings()

        XCTAssertNil(bag[int: "postsPerPage"], "a type change degrades to unset")
        XCTAssertEqual(bag[string: "postsPerPage"], "twenty-five")
        XCTAssertNil(bag[bool: "neverSet"])
    }

    func test_givenNilAssignment_whenWriting_thenRemovesTheKey() {
        var bag = AppSettingsBag()
        bag[bool: "syncEnabled"] = true
        XCTAssertEqual(bag[bool: "syncEnabled"], true)

        bag[bool: "syncEnabled"] = nil

        XCTAssertFalse(bag.keys.contains("syncEnabled"), "unset must round-trip as absence, not null")
        XCTAssertTrue(bag.isEmpty)
    }

    // MARK: - Upstream failure

    func test_givenForbidden_whenFetching_thenThrows() async {
        // Replaces an earlier test that asserted a 404 must throw. The live probe
        // showed 404 is the empty-bucket state, not an unknown-key rejection, so
        // the meaningful auth failure to cover here is 403.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "nope"))
        let service = makeService(api)

        do {
            _ = try await service.sharedSettings()
            XCTFail("Expected the failure to propagate")
        } catch {
            // expected
        }
    }

    // MARK: - First-run 404s
    //
    // Verified live 2026-09-06: the server answers 404 for an app key with
    // nothing stored yet, and 404 `{"source":"none"}` for a device it has not
    // seen. Both are ordinary first-run states — treating them as errors made a
    // fresh install show a failure instead of empty settings.

    func test_givenNothingStoredYet_whenReadingSharedSettings_thenReturnsEmptyBagNotAnError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Not found"))
        let service = makeService(api)

        let bag = try await service.sharedSettings()

        XCTAssertTrue(bag.isEmpty)
    }

    func test_givenUnregisteredDevice_whenBootstrapping_thenReturnsEmptySnapshotFlaggedNew() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Not found"))
        let service = makeService(api)

        let snapshot = try await service.bootstrap(deviceID: "dev-new")

        XCTAssertTrue(snapshot.shared.isEmpty)
        XCTAssertTrue(snapshot.device.isEmpty)
        XCTAssertTrue(snapshot.isNewDevice, "the caller registers off this flag")
    }

    func test_givenNothingStoredYet_whenReadingDeviceSettings_thenReturnsEmptyBag() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Not found"))
        let service = makeService(api)

        let bag = try await service.deviceSettings(deviceID: "dev-1")

        XCTAssertTrue(bag.isEmpty)
    }

    func test_givenRealFailure_whenReadingSettings_thenStillThrows() async {
        // Only 404 is benign. A 500 or a 401 must still reach the UI.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = makeService(api)

        do {
            _ = try await service.sharedSettings()
            XCTFail("a server error is not a first-run state")
        } catch {
            // expected
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoDevices_whenListing_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "devices": [] }"#)
        let service = makeService(api)

        let devices = try await service.devices()

        XCTAssertTrue(devices.isEmpty)
    }

    func test_givenEmptySettings_whenFetching_thenReturnsEmptyBag() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "settings": {} }"#)
        let service = makeService(api)

        let bag = try await service.sharedSettings()

        XCTAssertTrue(bag.isEmpty)
    }
}
