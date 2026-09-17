import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD coverage for `AppSettingsService`, `AppSettingsBag` and the device
/// registry (work-consolidation.md G17, GitHub issue #56).
///
/// The fixtures are the live shapes captured 2026-09-16; see
/// `AppSettingsEndpointTests` for the verbatim probe bodies they come from.
final class AppSettingsServiceTests: XCTestCase {

    private let appKey = "interlinedlist-macos"

    private func makeService(_ api: StubAPIClient) -> AppSettingsService {
        AppSettingsService(api: api, appKey: appKey)
    }

    private func documentJSON(version: Int = 1, settings: String = #"{"theme":"dark"}"#) -> String {
        """
        { "appKey": "interlinedlist-macos", "scope": "account", "deviceId": null,
          "version": \(version), "updatedAt": "2026-09-16T19:39:07.135Z",
          "schemaVersion": 1, "settings": \(settings) }
        """
    }

    // MARK: - Happy path

    func test_givenOwnDocument_whenBootstrapping_thenReportsOriginAndSettings() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "source": "self", "appKey": "interlinedlist-macos", "scope": "device",
          "deviceId": "dev-1", "version": 3, "updatedAt": "2026-09-16T19:39:18.084Z",
          "schemaVersion": 1,
          "settings": { "theme": "dark", "postsPerPage": 25, "syncFolder": "/Users/x/Notes" } }
        """#)
        let service = makeService(api)

        let seed = try await service.bootstrap(deviceID: "dev-1")

        XCTAssertEqual(seed.origin, .own)
        XCTAssertFalse(seed.isFirstRun)
        XCTAssertEqual(seed.bag[string: "theme"], "dark")
        XCTAssertEqual(seed.bag[int: "postsPerPage"], 25)
        XCTAssertEqual(seed.document?.version, 3)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/app-settings/interlinedlist-macos/bootstrap")
        XCTAssertEqual(recorded.first?.query["deviceId"], "dev-1")
    }

    func test_givenNewDevice_whenBootstrapping_thenNamesTheSeedingWorkstation() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "source": "default-device", "appKey": "interlinedlist-macos", "scope": "device",
          "deviceId": "dev-main", "version": 1, "updatedAt": "2026-09-16T19:39:18.084Z",
          "settings": { "theme": "dark" },
          "defaultDeviceId": "dev-main", "defaultDeviceName": "Studio Mac" }
        """#)
        let service = makeService(api)

        let seed = try await service.bootstrap(deviceID: "brand-new")

        // A new Mac arriving pre-configured is only explicable if the app can
        // say which machine it was seeded from.
        XCTAssertEqual(seed.origin, .mainWorkstation(deviceID: "dev-main", deviceName: "Studio Mac"))
        XCTAssertEqual(seed.bag[string: "theme"], "dark")
    }

    func test_givenDevices_whenListing_thenMapsRegistry() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "devices": [ { "deviceId": "dev-1", "deviceName": "Studio Mac", "platform": "macos",
                         "isDefault": true, "lastSeenAt": "2026-09-16T19:38:42.214Z",
                         "hasDeviceSettings": true },
                       { "deviceId": "dev-2", "deviceName": "Laptop", "isDefault": false,
                         "hasDeviceSettings": false } ] }
        """#)
        let service = makeService(api)

        let devices = try await service.devices()

        XCTAssertEqual(devices.map(\.id), ["dev-1", "dev-2"])
        // `isDefault` on the wire is the main-workstation role in the domain.
        XCTAssertTrue(devices[0].isMainWorkstation)
        XCTAssertFalse(devices[1].isMainWorkstation)
        XCTAssertEqual(devices[0].name, "Studio Mac")
        XCTAssertEqual(devices[0].platform, "macos")
        XCTAssertEqual(devices[0].hasDeviceSettings, true)
    }

    func test_givenRename_whenRenaming_thenUnwrapsTheDeviceEnvelope() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "device": { "deviceId": "dev-2", "deviceName": "Renamed", "isDefault": false } }
        """#)
        let service = makeService(api)

        let device = try await service.renameDevice(deviceID: "dev-2", to: "Renamed")

        XCTAssertEqual(device.name, "Renamed")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
    }

    func test_givenPromotion_whenMakingMainWorkstation_thenSendsOnlyTheFlag() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "device": { "deviceId": "dev-2", "deviceName": "Laptop", "isDefault": true } }
        """#)
        let service = makeService(api)

        let device = try await service.makeMainWorkstation(deviceID: "dev-2")

        XCTAssertTrue(device.isMainWorkstation)
        let recorded = await api.recorded
        let body = recorded.first?.bodyJSON
        XCTAssertEqual(body?["isDefault"] as? Bool, true)
        // A promotion that also sent the name would clobber a rename made on
        // another machine between this client's read and its write.
        XCTAssertNil(body?["deviceName"])
    }

    func test_givenMainWorkstationRemoved_whenDeregistering_thenReportsThePromotedMachine() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"deleted":true,"promotedDeviceId":"dev-1"}"#)
        let service = makeService(api)

        let outcome = try await service.deregisterDevice(deviceID: "dev-2")

        XCTAssertTrue(outcome.deleted)
        // The server names the successor, so the client never has to guess who
        // inherited the role.
        XCTAssertEqual(outcome.promotedDeviceID, "dev-1")
    }

    func test_givenStoredDocument_whenWritingShared_thenSendsTheVersionItRead() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: documentJSON(version: 4, settings: #"{"theme":"light"}"#))
        let service = makeService(api)
        var bag = AppSettingsBag()
        bag[string: "theme"] = "light"

        let saved = try await service.writeSharedSettings(bag, baseVersion: 3)

        XCTAssertEqual(saved.version, 4)
        let recorded = await api.recorded
        // Omitting baseVersion is a hard 400 on this API.
        XCTAssertEqual(recorded.first?.bodyJSON?["baseVersion"] as? Int, 3)
    }

    func test_givenDeviceSettings_whenCopyingToShared_thenReplacesUsingTheSharedVersion() async throws {
        let api = StubAPIClient()
        // 1. read the source device document
        await api.enqueue(json: #"""
        { "appKey": "interlinedlist-macos", "scope": "device", "deviceId": "dev-1",
          "version": 9, "updatedAt": "2026-09-16T19:39:18.084Z",
          "settings": { "syncFolder": "/Users/x/Notes" } }
        """#)
        // 2. read the destination for its version
        await api.enqueue(json: documentJSON(version: 2))
        // 3. the write
        await api.enqueue(json: documentJSON(version: 3, settings: #"{"syncFolder":"/Users/x/Notes"}"#))
        let service = makeService(api)

        let result = try await service.copyDeviceSettingsToShared(deviceID: "dev-1")

        XCTAssertEqual(result.bag[string: "syncFolder"], "/Users/x/Notes")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 3)
        // The write must carry the DESTINATION's version (2), not the source
        // document's (9) — they are independent documents with independent
        // version counters, and sending the source's would lose the write.
        XCTAssertEqual(recorded[2].bodyJSON?["baseVersion"] as? Int, 2)
        XCTAssertEqual(recorded[2].method, "PUT")
        XCTAssertEqual(recorded[2].path, "/api/user/app-settings/interlinedlist-macos")
    }

    func test_givenStoredSettings_whenDeletingShared_thenReportsDeletion() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"deleted":true}"#)
        let service = makeService(api)

        let deleted = try await service.deleteSharedSettings()

        XCTAssertTrue(deleted)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/user/app-settings/interlinedlist-macos")
    }

    // MARK: - Bag semantics

    func test_givenUnknownKeys_whenEditingAndWritingBack_thenUnknownKeysSurvive() async throws {
        // The forward-compatibility guarantee: an older build must not delete a
        // newer build's settings just by saving.
        let api = StubAPIClient()
        await api.enqueue(json: documentJSON(
            version: 1,
            settings: #"{"theme":"dark","futureFeature":{"nested":[1,2]}}"#
        ))
        await api.enqueue(json: documentJSON(
            version: 2,
            settings: #"{"theme":"light","futureFeature":{"nested":[1,2]}}"#
        ))
        let service = makeService(api)

        let loaded = try await service.sharedDocument()
        var document = try XCTUnwrap(loaded)
        document.bag[string: "theme"] = "light"
        let saved = try await service.writeSharedSettings(document.bag, baseVersion: document.version)

        XCTAssertEqual(saved.bag[string: "theme"], "light")
        let recorded = await api.recorded
        let sent = recorded[1].bodyJSON?["settings"] as? [String: Any]
        XCTAssertNotNil(sent?["futureFeature"], "a key this build does not understand must survive the round trip")
    }

    func test_givenWrongTypeOrMissingKey_whenReading_thenReturnsNilRatherThanTrapping() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: documentJSON(settings: #"{"count":"not-a-number"}"#))
        let service = makeService(api)

        let loaded = try await service.sharedDocument()
        let document = try XCTUnwrap(loaded)

        XCTAssertNil(document.bag[int: "count"], "a type change must degrade to unset, not crash")
        XCTAssertNil(document.bag[string: "absent"])
    }

    func test_givenNilAssignment_whenWriting_thenRemovesTheKey() {
        var bag = AppSettingsBag()
        bag[string: "theme"] = "dark"
        XCTAssertEqual(bag.keys, ["theme"])

        bag[string: "theme"] = nil

        // "Unset" must round-trip as absence, not as a JSON null.
        XCTAssertTrue(bag.isEmpty)
    }

    func test_givenPayload_whenMeasuringSize_thenReportsEncodedBytes() {
        var bag = AppSettingsBag()
        bag[string: "theme"] = "dark"

        // The pane shows a size because the blob is opaque to this app as well
        // as to the server, and the server caps it.
        XCTAssertGreaterThan(bag.byteSize, 0)
        XCTAssertEqual(AppSettingsBag().byteSize, 2, "an empty payload encodes as {}")
    }

    // MARK: - Upstream failure

    func test_givenForbidden_whenFetching_thenThrows() async {
        // 404 is the empty-bucket state, not an auth rejection, so the
        // meaningful failure to cover here is 403.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "nope"))
        let service = makeService(api)

        do {
            _ = try await service.sharedDocument()
            XCTFail("Expected the failure to propagate")
        } catch {
            // expected
        }
    }

    func test_givenStaleVersion_whenWriting_thenThrowsVersionConflict() async {
        // A lost compare-and-set writes nothing, so the caller must be told to
        // reload rather than shown a generic HTTP error it cannot act on.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 409, serverMessage: "version_conflict"))
        let service = makeService(api)

        do {
            _ = try await service.writeSharedSettings(AppSettingsBag(), baseVersion: 1)
            XCTFail("Expected a version conflict")
        } catch let error as AppSettingsError {
            XCTAssertEqual(error, .versionConflict)
        } catch {
            XCTFail("Expected AppSettingsError.versionConflict, got \(error)")
        }
    }

    func test_givenUnregisteredDevice_whenWritingDeviceSettings_thenThrowsDeviceNotRegistered() async {
        // A 404 from the WRITE route means the device is missing from the
        // registry, not that the document is absent — `baseVersion: 0` creates
        // one happily. Mapping it to "empty" the way the read path does would
        // silently discard the user's settings.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "device not registered"))
        let service = makeService(api)

        do {
            _ = try await service.writeDeviceSettings(AppSettingsBag(), deviceID: "ghost", baseVersion: 0)
            XCTFail("Expected deviceNotRegistered")
        } catch let error as AppSettingsError {
            XCTAssertEqual(error, .deviceNotRegistered)
        } catch {
            XCTFail("Expected AppSettingsError.deviceNotRegistered, got \(error)")
        }
    }

    // MARK: - First-run 404s
    //
    // Verified live 2026-09-16: the server answers 404 for an app key with
    // nothing stored yet, and 404 `{"source":"none"}` for a device it has not
    // seen. Both are ordinary first-run states — treating them as errors made a
    // fresh install show a failure instead of empty settings.

    func test_givenNothingStoredYet_whenReadingSharedSettings_thenReturnsNilNotAnError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Not found"))
        let service = makeService(api)

        let document = try await service.sharedDocument()

        XCTAssertNil(document)
    }

    func test_givenNothingStoredAnywhere_whenBootstrapping_thenReturnsFirstRunSeed() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: #"{"source":"none"}"#))
        let service = makeService(api)

        let seed = try await service.bootstrap(deviceID: "dev-new")

        XCTAssertTrue(seed.isFirstRun)
        XCTAssertEqual(seed.origin, .none)
        XCTAssertTrue(seed.bag.isEmpty)
    }

    func test_givenNothingStoredYet_whenReadingDeviceSettings_thenReturnsNil() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Not found"))
        let service = makeService(api)

        let document = try await service.deviceDocument(deviceID: "dev-1")

        XCTAssertNil(document)
    }

    // MARK: - Empty / boundary

    func test_givenNoDevices_whenListing_thenReturnsEmpty() async throws {
        // The registry answers 200 with an empty array rather than 404.
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "devices": [] }"#)
        let service = makeService(api)

        let devices = try await service.devices()

        XCTAssertTrue(devices.isEmpty)
    }

    func test_givenMachineWithNoSettings_whenCopyingToShared_thenRefusesRatherThanWipingShared() async throws {
        // Copy-to-shared replaces wholesale, so copying "nothing" would delete
        // every shared setting. Refuse instead — and make sure no write is sent.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Not found"))
        let service = makeService(api)

        do {
            _ = try await service.copyDeviceSettingsToShared(deviceID: "dev-1")
            XCTFail("Expected noSettingsToCopy")
        } catch let error as AppSettingsError {
            XCTAssertEqual(error, .noSettingsToCopy)
        }

        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1, "the read must not be followed by a destructive write")
    }

    func test_givenLastDeviceRemoved_whenDeregistering_thenPromotesNobody() async throws {
        // Boundary: exactly one registered device, and it is the main
        // workstation. Nothing remains to inherit the role.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"deleted":true,"promotedDeviceId":null}"#)
        let service = makeService(api)

        let outcome = try await service.deregisterDevice(deviceID: "only-one")

        XCTAssertTrue(outcome.deleted)
        XCTAssertNil(outcome.promotedDeviceID)
    }

    func test_givenNothingToDelete_whenDeletingShared_thenReportsFalseWithoutThrowing() async throws {
        // Idempotent: `{"deleted":false}`, not a 404.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"deleted":false}"#)
        let service = makeService(api)

        let deleted = try await service.deleteSharedSettings()

        XCTAssertFalse(deleted)
    }

    func test_givenEmptySettings_whenFetching_thenReturnsEmptyBag() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: documentJSON(settings: "{}"))
        let service = makeService(api)

        let loaded = try await service.sharedDocument()
        let document = try XCTUnwrap(loaded)

        XCTAssertTrue(document.isEmpty)
        XCTAssertEqual(document.version, 1)
    }
}
