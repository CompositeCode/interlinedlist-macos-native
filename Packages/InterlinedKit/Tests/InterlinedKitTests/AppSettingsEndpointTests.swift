import XCTest
@testable import InterlinedKit

/// BDD tests for the app-settings + device-registry endpoints
/// (work-consolidation.md G17).
///
/// The live response shapes are unverified, so the decode tests deliberately
/// cover *both* envelope conventions this API has been seen to use (named key
/// vs. bare) rather than pinning one guess.
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

        let write = AppSettings.writeShared(appKey: appKey, WriteAppSettingsRequest(settings: [:]))
        XCTAssertEqual(write.method, .put)

        XCTAssertEqual(AppSettings.deleteShared(appKey: appKey).method, .delete)

        let bootstrap = AppSettings.bootstrap(appKey: appKey, deviceId: "dev-1")
        XCTAssertEqual(bootstrap.path, "/api/user/app-settings/interlinedlist-macos/bootstrap")
        XCTAssertTrue(bootstrap.query.contains(.string("deviceId", "dev-1")))

        XCTAssertEqual(AppSettings.devices(appKey: appKey).path, "/api/user/app-settings/interlinedlist-macos/devices")
        XCTAssertEqual(AppSettings.registerDevice(appKey: appKey, RegisterDeviceRequest(deviceId: "dev-1")).method, .post)
        XCTAssertEqual(AppSettings.updateDevice(appKey: appKey, deviceId: "dev-1", UpdateDeviceRequest(name: "Mac")).method, .patch)
        XCTAssertEqual(AppSettings.deleteDevice(appKey: appKey, deviceId: "dev-1").method, .delete)
        XCTAssertEqual(
            AppSettings.deviceSettings(appKey: appKey, deviceId: "dev-1").path,
            "/api/user/app-settings/interlinedlist-macos/devices/dev-1/settings"
        )
        XCTAssertEqual(
            AppSettings.writeDeviceSettings(appKey: appKey, deviceId: "dev-1", WriteAppSettingsRequest(settings: [:])).method,
            .put
        )
        // Every builder is Bearer.
        XCTAssertEqual(AppSettings.devices(appKey: appKey).auth, .bearer)
    }

    // MARK: - Happy path

    func test_givenWrappedSettings_whenSharedSent_thenDecodesPayload() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "settings": { "theme": "dark", "postsPerPage": 25, "syncEnabled": true },
          "updatedAt": "2026-09-05T10:00:00Z" }
        """#))

        let dto = try await client.send(AppSettings.shared(appKey: appKey))

        XCTAssertEqual(dto.settings["theme"]?.stringValue, "dark")
        XCTAssertEqual(dto.settings["postsPerPage"]?.intValue, 25)
        XCTAssertEqual(dto.settings["syncEnabled"]?.boolValue, true)
        XCTAssertEqual(dto.updatedAt, JSONCoders.parseDate("2026-09-05T10:00:00Z"))
    }

    func test_givenDevicesBody_whenSent_thenDecodesRegistry() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "devices": [
            { "deviceId": "dev-1", "name": "Studio Mac", "isMainWorkstation": true,
              "lastSeenAt": "2026-09-05T09:00:00Z" },
            { "id": "dev-2", "deviceLabel": "Laptop", "isMain": false }
        ] }
        """#))

        let response = try await client.send(AppSettings.devices(appKey: appKey))

        XCTAssertEqual(response.devices.count, 2)
        XCTAssertEqual(response.devices[0].deviceId, "dev-1")
        XCTAssertEqual(response.devices[0].isMainWorkstation, true)
        // Second row uses the alternate `id` / `deviceLabel` / `isMain` spelling.
        XCTAssertEqual(response.devices[1].deviceId, "dev-2")
        XCTAssertEqual(response.devices[1].name, "Laptop")
        XCTAssertEqual(response.devices[1].isMainWorkstation, false)
    }

    func test_givenBootstrapBody_whenSent_thenSplitsSharedAndDeviceSettings() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        { "shared": { "theme": "dark" },
          "device": { "syncFolder": "/Users/x/Notes" },
          "isNewDevice": true, "seededFromMainWorkstation": true }
        """#))

        let dto = try await client.send(AppSettings.bootstrap(appKey: appKey, deviceId: "dev-9"))

        XCTAssertEqual(dto.shared["theme"]?.stringValue, "dark")
        XCTAssertEqual(dto.device["syncFolder"]?.stringValue, "/Users/x/Notes")
        XCTAssertEqual(dto.isNewDevice, true)
        XCTAssertEqual(dto.seededFromMainWorkstation, true)
    }

    // MARK: - Invalid / tolerant input

    func test_givenBareSettingsObject_whenSharedSent_thenTreatsBodyAsPayload() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "theme": "light", "updatedAt": "2026-09-05T10:00:00Z" }"#))

        let dto = try await client.send(AppSettings.shared(appKey: appKey))

        XCTAssertEqual(dto.settings["theme"]?.stringValue, "light")
        // Metadata must not leak into the settings payload.
        XCTAssertNil(dto.settings["updatedAt"])
        XCTAssertEqual(dto.updatedAt, JSONCoders.parseDate("2026-09-05T10:00:00Z"))
    }

    func test_givenAlternateBootstrapKeys_whenSent_thenStillDecodes() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "sharedSettings": { "a": 1 }, "deviceSettings": { "b": 2 } }"#))

        let dto = try await client.send(AppSettings.bootstrap(appKey: appKey, deviceId: "dev-9"))

        XCTAssertEqual(dto.shared["a"]?.intValue, 1)
        XCTAssertEqual(dto.device["b"]?.intValue, 2)
    }

    func test_givenNestedAndUnknownKeys_whenRoundTripped_thenPreservedVerbatim() throws {
        // The forward-compatibility guarantee: a payload written by a newer
        // build must survive decode -> encode unchanged.
        let raw = #"{ "settings": { "known": true, "futureFeature": { "nested": [1, "two", null] } } }"#
        let dto = try JSONDecoder().decode(AppSettingsDTO.self, from: Data(raw.utf8))

        let reEncoded = try JSONEncoder().encode(WriteAppSettingsRequest(settings: dto.settings))
        let round = try JSONDecoder().decode(AppSettingsDTO.self, from: reEncoded)

        XCTAssertEqual(round.settings["known"]?.boolValue, true)
        let nested = round.settings["futureFeature"]?["nested"]?.arrayValue
        XCTAssertEqual(nested?.count, 3)
        XCTAssertEqual(nested?[1].stringValue, "two")
        XCTAssertEqual(nested?[2], .null)
    }

    // MARK: - API failure

    func test_givenUnregisteredAppKey_whenSent_thenThrowsNotFoundWithMessage() async throws {
        // 404 maps to `.notFound`, not `.httpStatus` — the client narrows the
        // well-known statuses and carries the server's message through.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"unknown app key"}"#, status: 404))

        do {
            _ = try await client.send(AppSettings.shared(appKey: "not-registered"))
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "unknown app key"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenNoDevices_whenSent_thenReturnsEmptyRegistry() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "devices": [] }"#))

        let response = try await client.send(AppSettings.devices(appKey: appKey))

        XCTAssertTrue(response.devices.isEmpty)
    }

    func test_givenEmptySettings_whenSent_thenDecodesEmptyPayload() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{ "settings": {} }"#))

        let dto = try await client.send(AppSettings.shared(appKey: appKey))

        XCTAssertTrue(dto.settings.isEmpty)
        XCTAssertNil(dto.updatedAt)
    }
}
