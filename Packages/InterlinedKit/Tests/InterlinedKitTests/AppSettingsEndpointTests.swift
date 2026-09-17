import XCTest
@testable import InterlinedKit

/// BDD tests for the app-settings + device-registry endpoints
/// (work-consolidation.md G17, GitHub issue #56).
///
/// Every payload below is a **verbatim live response** captured on 2026-09-16
/// against the test account, by storing real settings and registering real
/// devices and then re-reading them. The shapes were guesses before that; the
/// guesses were wrong in five separate places, so these fixtures are pinned to
/// what the server actually sends rather than to what seemed reasonable.
final class AppSettingsEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!
    private let appKey = "interlinedlist-macos"

    private func makeClient() -> (APIClient, StubHTTPDataTransport) {
        let transport = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_abc"),
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        return (APIClient(baseURL: baseURL, transport: transport, authTransport: auth), transport)
    }

    // MARK: - Builder shape

    func test_givenBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(AppSettings.shared(appKey: appKey).path, "/api/user/app-settings/interlinedlist-macos")
        XCTAssertEqual(AppSettings.shared(appKey: appKey).method, .get)

        let write = AppSettings.writeShared(
            appKey: appKey,
            WriteAppSettingsRequest(settings: [:], baseVersion: 0)
        )
        XCTAssertEqual(write.method, .put)

        XCTAssertEqual(AppSettings.deleteShared(appKey: appKey).method, .delete)

        let bootstrap = AppSettings.bootstrap(appKey: appKey, deviceId: "dev-1")
        XCTAssertEqual(bootstrap.path, "/api/user/app-settings/interlinedlist-macos/bootstrap")
        XCTAssertTrue(bootstrap.query.contains(.string("deviceId", "dev-1")))

        XCTAssertEqual(AppSettings.devices(appKey: appKey).path, "/api/user/app-settings/interlinedlist-macos/devices")
        XCTAssertEqual(
            AppSettings.registerDevice(
                appKey: appKey,
                RegisterDeviceRequest(deviceId: "dev-1", deviceName: "Mac")
            ).method,
            .post
        )
        XCTAssertEqual(
            AppSettings.updateDevice(appKey: appKey, deviceId: "dev-1", UpdateDeviceRequest(deviceName: "Mac")).method,
            .patch
        )
        XCTAssertEqual(AppSettings.deleteDevice(appKey: appKey, deviceId: "dev-1").method, .delete)
        XCTAssertEqual(
            AppSettings.deviceSettings(appKey: appKey, deviceId: "dev-1").path,
            "/api/user/app-settings/interlinedlist-macos/devices/dev-1/settings"
        )
        XCTAssertEqual(
            AppSettings.writeDeviceSettings(
                appKey: appKey,
                deviceId: "dev-1",
                WriteAppSettingsRequest(settings: [:], baseVersion: 3)
            ).method,
            .put
        )
        // Every builder is Bearer.
        XCTAssertEqual(AppSettings.devices(appKey: appKey).auth, .bearer)
    }

    // MARK: - Request bodies

    func test_givenWriteRequest_whenEncoded_thenCarriesBaseVersion() throws {
        // Omitting `baseVersion` is a hard 400 — "baseVersion must be an
        // integer >= 0" — so it must appear on the wire, including when it is
        // the create-sentinel 0, which `encodeIfPresent` semantics would be apt
        // to drop.
        let body = WriteAppSettingsRequest(settings: ["theme": .string("dark")], baseVersion: 0)

        let json = try JSONSerialization.jsonObject(
            with: JSONCoders.makeEncoder().encode(body)
        ) as? [String: Any]

        XCTAssertEqual(json?["baseVersion"] as? Int, 0)
        XCTAssertNotNil(json?["settings"])
    }

    func test_givenDeviceUpdate_whenEncoded_thenUsesDeviceNameAndIsDefault() throws {
        // The server rejects anything else outright: "at least one of
        // deviceName or isDefault is required".
        let rename = try JSONSerialization.jsonObject(
            with: JSONCoders.makeEncoder().encode(UpdateDeviceRequest(deviceName: "Studio Mac"))
        ) as? [String: Any]
        XCTAssertEqual(rename?["deviceName"] as? String, "Studio Mac")
        XCTAssertNil(rename?["isDefault"], "a rename must not also send the promotion flag")

        let promote = try JSONSerialization.jsonObject(
            with: JSONCoders.makeEncoder().encode(UpdateDeviceRequest(isDefault: true))
        ) as? [String: Any]
        XCTAssertEqual(promote?["isDefault"] as? Bool, true)
        XCTAssertNil(promote?["deviceName"], "a promotion must not clobber a rename from another machine")
    }

    // MARK: - Happy path

    func test_givenStoredSettings_whenSharedSent_thenDecodesBareDocument() async throws {
        let (client, transport) = makeClient()
        // Verbatim live body, 2026-09-16.
        await transport.enqueue(.json(#"""
        { "appKey": "interlinedlist-macos", "scope": "account", "deviceId": null,
          "version": 1, "updatedAt": "2026-09-16T19:39:07.135Z", "schemaVersion": 1,
          "settings": { "theme": "dark", "sidebarWidth": 280 } }
        """#))

        let dto = try await client.send(AppSettings.shared(appKey: appKey))

        XCTAssertEqual(dto.version, 1)
        XCTAssertEqual(dto.scope, "account")
        XCTAssertNil(dto.deviceId)
        XCTAssertEqual(dto.settings["theme"]?.stringValue, "dark")
        XCTAssertEqual(dto.settings["sidebarWidth"]?.intValue, 280)
        XCTAssertEqual(dto.updatedAt, JSONCoders.parseDate("2026-09-16T19:39:07.135Z"))
        // Metadata must never leak into the opaque payload and get written back.
        XCTAssertNil(dto.settings["appKey"])
        XCTAssertNil(dto.settings["version"])
    }

    func test_givenDevicesBody_whenSent_thenDecodesRegistry() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "devices": [
            { "deviceId": "probe-mac-beta", "deviceName": "Probe Beta", "platform": "macos",
              "isDefault": false, "lastSeenAt": "2026-09-16T19:38:50.810Z",
              "appVersion": null, "osVersion": null, "hasDeviceSettings": false },
            { "deviceId": "probe-mac-alpha", "deviceName": "Probe Alpha", "platform": "macos",
              "isDefault": true, "lastSeenAt": "2026-09-16T19:38:42.214Z",
              "appVersion": null, "osVersion": null, "hasDeviceSettings": true }
        ] }
        """#))

        let response = try await client.send(AppSettings.devices(appKey: appKey))

        XCTAssertEqual(response.devices.count, 2)
        // `deviceName` and `isDefault` — the previous decoder looked for `name`
        // and `isMainWorkstation`, so every row lost its name and its badge.
        XCTAssertEqual(response.devices[1].deviceName, "Probe Alpha")
        XCTAssertTrue(response.devices[1].isDefault)
        XCTAssertFalse(response.devices[0].isDefault)
        XCTAssertEqual(response.devices[1].hasDeviceSettings, true)
        XCTAssertEqual(response.devices[0].platform, "macos")
    }

    func test_givenRegisterResponse_whenSent_thenDecodesThroughTheDeviceEnvelope() async throws {
        let (client, transport) = makeClient()
        // POST and PATCH both wrap the device; decoding it bare threw on success.
        await transport.enqueue(.json(#"""
        { "device": { "deviceId": "probe-mac-alpha", "deviceName": "Probe Alpha",
                      "platform": "macos", "isDefault": true,
                      "lastSeenAt": "2026-09-16T19:38:42.214Z",
                      "appVersion": null, "osVersion": null } }
        """#))

        let envelope = try await client.send(
            AppSettings.registerDevice(
                appKey: appKey,
                RegisterDeviceRequest(deviceId: "probe-mac-alpha", deviceName: "Probe Alpha")
            )
        )

        XCTAssertEqual(envelope.device.deviceId, "probe-mac-alpha")
        XCTAssertEqual(envelope.device.deviceName, "Probe Alpha")
        // The first device registered is made main workstation automatically.
        XCTAssertTrue(envelope.device.isDefault)
        // Absent on this route — must stay nil rather than default to false.
        XCTAssertNil(envelope.device.hasDeviceSettings)
    }

    func test_givenMainWorkstationRemoved_whenDeleted_thenReportsThePromotedDevice() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"deleted":true,"promotedDeviceId":"probe-mac-alpha"}"#))

        let response = try await client.send(
            AppSettings.deleteDevice(appKey: appKey, deviceId: "probe-mac-beta")
        )

        XCTAssertTrue(response.deleted)
        // The server names the successor, so no client ever has to guess.
        XCTAssertEqual(response.promotedDeviceId, "probe-mac-alpha")
    }

    func test_givenOwnSettings_whenBootstrapping_thenDecodesSourceAndDocument() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "source": "self", "appKey": "interlinedlist-macos", "scope": "device",
          "deviceId": "probe-mac-alpha", "version": 1,
          "updatedAt": "2026-09-16T19:39:18.084Z", "schemaVersion": 1,
          "settings": { "windowFrame": "0,0,1440,900", "syncFolderPath": "/Users/probe/Obsidian" } }
        """#))

        let dto = try await client.send(AppSettings.bootstrap(appKey: appKey, deviceId: "probe-mac-alpha"))

        XCTAssertEqual(dto.source, .own)
        // The document fields sit alongside `source`, not nested under a key.
        XCTAssertEqual(dto.document?.version, 1)
        XCTAssertEqual(dto.document?.settings["syncFolderPath"]?.stringValue, "/Users/probe/Obsidian")
    }

    func test_givenNewDevice_whenBootstrapping_thenNamesTheSeedingWorkstation() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "source": "default-device", "appKey": "interlinedlist-macos", "scope": "device",
          "deviceId": "probe-mac-alpha", "version": 1,
          "updatedAt": "2026-09-16T19:39:18.084Z", "schemaVersion": 1,
          "settings": { "windowFrame": "0,0,1440,900" },
          "defaultDeviceId": "probe-mac-alpha", "defaultDeviceName": "Probe Alpha" }
        """#))

        let dto = try await client.send(AppSettings.bootstrap(appKey: appKey, deviceId: "brand-new"))

        XCTAssertEqual(dto.source, .defaultDevice)
        XCTAssertEqual(dto.defaultDeviceName, "Probe Alpha")
        // `deviceId` on the document is the SOURCE machine, not the one asked
        // about — a new Mac is being handed the main workstation's document.
        XCTAssertEqual(dto.document?.deviceId, "probe-mac-alpha")
    }

    func test_givenNoDeviceSettingsAnywhere_whenBootstrapping_thenFallsBackToAccountScope() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "source": "account", "appKey": "interlinedlist-macos", "scope": "account",
          "deviceId": null, "version": 1, "updatedAt": "2026-09-16T19:39:07.135Z",
          "schemaVersion": 1, "settings": { "theme": "dark" } }
        """#))

        let dto = try await client.send(AppSettings.bootstrap(appKey: appKey, deviceId: "brand-new"))

        // The precedence chain is own -> main workstation -> account -> none.
        XCTAssertEqual(dto.source, .account)
        XCTAssertEqual(dto.document?.settings["theme"]?.stringValue, "dark")
        XCTAssertNil(dto.document?.deviceId)
    }

    // MARK: - Invalid / tolerant input

    func test_givenNestedAndUnknownKeys_whenRoundTripped_thenPreservedVerbatim() throws {
        // The forward-compatibility guarantee: a payload written by a newer
        // build must survive decode -> encode unchanged, or this client silently
        // deletes settings it does not understand.
        let raw = #"""
        { "appKey": "k", "scope": "account", "version": 2, "updatedAt": "2026-09-16T19:39:07.135Z",
          "settings": { "known": true, "futureFeature": { "nested": [1, "two", null] } } }
        """#
        let dto = try JSONCoders.makeDecoder().decode(AppSettingsDocumentDTO.self, from: Data(raw.utf8))

        let reEncoded = try JSONCoders.makeEncoder().encode(
            WriteAppSettingsRequest(settings: dto.settings, baseVersion: dto.version)
        )
        let sent = try JSONSerialization.jsonObject(with: reEncoded) as? [String: Any]
        let settings = sent?["settings"] as? [String: Any]
        let nested = (settings?["futureFeature"] as? [String: Any])?["nested"] as? [Any]

        XCTAssertEqual(settings?["known"] as? Bool, true)
        XCTAssertEqual(nested?.count, 3)
        XCTAssertEqual(nested?[1] as? String, "two")
        // And the version read is the version written back.
        XCTAssertEqual(sent?["baseVersion"] as? Int, 2)
    }

    func test_givenBlankDeviceName_whenDecoded_thenStillDecodesRatherThanThrowing() async throws {
        // `deviceName` is required by the schema and always present live, but an
        // empty string must not take the whole registry down with it — the
        // domain layer substitutes the id for display.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "devices": [ { "deviceId": "dev-1", "deviceName": "", "isDefault": false } ] }
        """#))

        let response = try await client.send(AppSettings.devices(appKey: appKey))

        XCTAssertEqual(response.devices.first?.deviceName, "")
        XCTAssertNil(response.devices.first?.lastSeenAt)
    }

    // MARK: - API failure

    func test_givenNothingStored_whenSharedSent_thenThrowsNotFoundWithMessage() async throws {
        // 404 is the ordinary first-run answer for an app key with nothing
        // stored; the domain layer maps it to "no document". It must still
        // arrive as `.notFound` and not `.httpStatus`.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Not found","code":"not_found"}"#, status: 404))

        do {
            _ = try await client.send(AppSettings.shared(appKey: appKey))
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Not found"))
        }
    }

    func test_givenStaleBaseVersion_whenWriting_thenSurfacesConflictStatus() async throws {
        // A lost compare-and-set. 409 is not one of the statuses APIError
        // narrows, so it must arrive as `.httpStatus(409)` for the domain layer
        // to translate — nothing was written.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "error": "version_conflict", "code": "version_conflict",
          "current": { "appKey": "interlinedlist-macos", "scope": "account", "deviceId": null,
                       "version": 1, "updatedAt": "2026-09-16T19:39:07.135Z",
                       "schemaVersion": 1, "settings": { "theme": "dark" } } }
        """#, status: 409))

        do {
            _ = try await client.send(
                AppSettings.writeShared(
                    appKey: appKey,
                    WriteAppSettingsRequest(settings: [:], baseVersion: 0)
                )
            )
            XCTFail("Expected a 409")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatusCode, 409)
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoDevices_whenSent_thenReturnsEmptyRegistry() async throws {
        // Verified live: the registry answers 200 with an empty array on a fresh
        // account rather than 404, unlike the settings routes.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "devices": [] }"#))

        let response = try await client.send(AppSettings.devices(appKey: appKey))

        XCTAssertTrue(response.devices.isEmpty)
    }

    func test_givenNothingToDelete_whenDeletingShared_thenReportsNotDeletedRatherThan404() async throws {
        // Verified live: this delete is idempotent — `{"deleted":false}`, no 404.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"deleted":false}"#))

        let response = try await client.send(AppSettings.deleteShared(appKey: appKey))

        XCTAssertFalse(response.deleted)
    }

    func test_givenNothingStoredAnywhere_whenBootstrapping_thenSourceIsNoneWithNoDocument() async throws {
        // The 404 first-run body. `source` still decodes, and there is no
        // document to speak of.
        let dto = try JSONCoders.makeDecoder().decode(
            AppSettingsBootstrapDTO.self,
            from: Data(#"{"source":"none"}"#.utf8)
        )

        XCTAssertEqual(dto.source, .none)
        XCTAssertNil(dto.document)
    }
}
