import XCTest
@testable import InterlinedListSyncCore

/// Intercepts URLSession traffic so the client can be tested without a network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

final class SyncAPIClientTests: XCTestCase {

    private func makeClient(token: String? = "il_tok_test") -> SyncAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return SyncAPIClient(
            baseURL: URL(string: "https://interlinedlist.com")!,
            tokenProvider: StaticTokenProvider(token),
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func test_fetchDelta_sendsBearerAndLastSyncAt_andDecodes() async throws {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer il_tok_test")
            XCTAssertEqual(request.url?.path, "/api/documents/sync")
            XCTAssertTrue(request.url?.query?.contains("lastSyncAt=") ?? false)
            let (r, d) = (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                          Data(#"{"lastSyncAt":"2026-01-01T00:00:00.000Z","documents":[{"id":"a","title":"A","content":"x","updatedAt":"2026-01-01T00:00:00.000Z"}],"folders":[]}"#.utf8))
            return (r, d)
        }
        let client = makeClient()
        let delta = try await client.fetchDelta(since: since)
        XCTAssertEqual(delta.documents.first?.id, "a")
    }

    func test_createDocument_decodesEnvelope() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let json = #"{"document":{"id":"new","title":"New","content":"hi","updatedAt":"2026-01-01T00:00:00.000Z"},"message":"created"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let client = makeClient()
        let doc = try await client.createDocument(CreateDocumentBody(title: "New", content: "hi"))
        XCTAssertEqual(doc.id, "new")
    }

    func test_missingToken_throwsNoToken() async {
        let client = makeClient(token: nil)
        do {
            _ = try await client.fetchAllDocuments()
            XCTFail("expected noToken")
        } catch {
            XCTAssertEqual(error as? APIError, .noToken)
        }
    }

    func test_401_mapsToUnauthorized() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.fetchDelta(since: nil)
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func test_delete_treats404AsSuccess() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = makeClient()
        try await client.deleteDocument(id: "gone") // must not throw
    }

    // MARK: - Per-machine app settings (GitHub issue #104)
    //
    // Path, method and body are asserted together on purpose. A wrong body is
    // as breaking as a wrong path and far quieter — PR #102 found this exact
    // family shipping `{"name":…}` for weeks while every path assertion passed.

    func test_givenAConfiguredMachine_whenWritingSettings_thenItPutsToTheDeviceRouteWithABaseVersion() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(
                request.url?.path,
                "/api/user/app-settings/interlinedlist-macos/devices/mac-1/settings"
            )
            let body = try XCTUnwrap(request.httpBodyStream.map { stream -> Data in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                return data
            } ?? request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["baseVersion"] as? Int, 3)
            XCTAssertEqual(json["schemaVersion"] as? Int, SyncConfiguration.settingsSchemaVersion)
            let settings = try XCTUnwrap(json["settings"] as? [String: Any])
            XCTAssertEqual(settings[DocumentSyncSettingsKeys.enabled] as? Bool, true)

            let response = #"{"appKey":"interlinedlist-macos","scope":"device","deviceId":"mac-1","version":4,"updatedAt":"2026-09-16T19:39:07.135Z","schemaVersion":1,"settings":{"documentSync.enabled":true}}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }
        let client = makeClient()

        let document = try await client.writeDeviceSettings(
            deviceId: "mac-1",
            settings: [DocumentSyncSettingsKeys.enabled: .bool(true)],
            baseVersion: 3
        )

        XCTAssertEqual(document.version, 4)
        XCTAssertEqual(document.deviceId, "mac-1")
    }

    func test_givenAMachineThatHasNeverStoredSettings_whenReading_thenItAnswersNilRatherThanThrowing() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data(#"{"error":"Not found","code":"not_found"}"#.utf8)
            )
        }
        let client = makeClient()

        let document = try await client.fetchDeviceSettings(deviceId: "mac-1")

        // First run, not a failure. The caller has to be able to tell this from
        // "the request failed", because only this one may trigger a migration.
        XCTAssertNil(document)
    }

    func test_givenAStaleBaseVersion_whenWritingSettings_thenTheConflictCarriesTheWinningDocument() async {
        MockURLProtocol.handler = { request in
            let response = #"{"error":"version_conflict","code":"version_conflict","current":{"appKey":"interlinedlist-macos","scope":"device","deviceId":"mac-1","version":9,"schemaVersion":1,"settings":{"theme":"dark"}}}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }
        let client = makeClient()

        do {
            _ = try await client.writeDeviceSettings(deviceId: "mac-1", settings: [:], baseVersion: 1)
            XCTFail("expected a version conflict")
        } catch APIError.versionConflict(let current) {
            // Lifting `current` out of the 409 is what lets a background retry
            // re-base without spending another request.
            XCTAssertEqual(current?.version, 9)
            XCTAssertEqual(current?.settings["theme"]?.stringValue, "dark")
        } catch {
            XCTFail("expected a version conflict, got \(error)")
        }
    }

    func test_givenAnUnparseableConflictBody_whenWritingSettings_thenItStillSurfacesAsAConflict() async {
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!,
                Data("not json".utf8)
            )
        }
        let client = makeClient()

        do {
            _ = try await client.writeDeviceSettings(deviceId: "mac-1", settings: [:], baseVersion: 1)
            XCTFail("expected a version conflict")
        } catch APIError.versionConflict(let current) {
            // The retry falls back to a fresh read rather than the whole write
            // failing on a decoding error.
            XCTAssertNil(current)
        } catch {
            XCTFail("expected a version conflict, got \(error)")
        }
    }

    func test_givenAnUnregisteredMachine_whenWritingSettings_thenItIsNotMistakenForAnEmptyDocument() async {
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data(#"{"error":"device not registered"}"#.utf8)
            )
        }
        let client = makeClient()

        do {
            _ = try await client.writeDeviceSettings(deviceId: "mac-1", settings: [:], baseVersion: 0)
            XCTFail("expected deviceNotRegistered")
        } catch {
            // `baseVersion: 0` creates a document happily, so a 404 here can only
            // mean the device is missing — mapping it to "empty" would silently
            // discard the user's settings.
            XCTAssertEqual(error as? APIError, .deviceNotRegistered)
        }
    }

    func test_givenAnUnregisteredMachine_whenRegistering_thenItPostsTheLiveFieldNames() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/user/app-settings/interlinedlist-macos/devices")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"device":{"deviceId":"mac-1","deviceName":"Studio Mac","isDefault":true}}"#.utf8)
            )
        }
        let client = makeClient()

        try await client.registerDevice(deviceId: "mac-1", deviceName: "Studio Mac")
    }
}
