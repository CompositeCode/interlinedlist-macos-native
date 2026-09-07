import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD coverage for `NotificationPreferencesService` (work-consolidation.md G18).
final class NotificationPreferencesServiceTests: XCTestCase {

    // MARK: - Happy path

    func test_givenCatalogue_whenFetching_thenMapsServerDrivenLabels() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "events": [
            { "key": "dig", "label": "Digs on your messages",
              "description": "When someone digs a message you wrote.",
              "channels": { "push": true, "inApp": true } } ] }
        """#)
        let service = NotificationPreferencesService(api: api)

        let events = try await service.catalogue()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].key, "dig")
        XCTAssertEqual(events[0].label, "Digs on your messages")
        XCTAssertEqual(events[0].description, "When someone digs a message you wrote.")
        XCTAssertEqual(events[0].channels.push, true)
        // A channel the server never mentions stays nil, so the pane can hide it
        // rather than render a dead switch.
        XCTAssertNil(events[0].channels.email)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/user/notification-preferences")
    }

    func test_givenEditedChannels_whenUpdating_thenPatchesAndReturnsServerCopy() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "events": [ { "key": "dig", "label": "Digs", "channels": { "push": false, "inApp": true } } ] }
        """#)
        let service = NotificationPreferencesService(api: api)
        var event = NotificationEventPreference(key: "dig", label: "Digs")
        event.channels.push = false

        let updated = try await service.update([event])

        XCTAssertEqual(updated[0].channels.push, false)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
    }

    // MARK: - Invalid / incomplete input

    func test_givenEventWithoutLabel_whenFetching_thenFallsBackToKey() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "events": [ { "key": "mention" } ] }"#)
        let service = NotificationPreferencesService(api: api)

        let events = try await service.catalogue()

        XCTAssertEqual(events[0].label, "mention", "an unlabelled event must still render")
        XCTAssertNil(events[0].channels.push)
    }

    // MARK: - Upstream failure

    func test_givenServerFailure_whenFetching_thenThrows() async {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = NotificationPreferencesService(api: api)

        do {
            _ = try await service.catalogue()
            XCTFail("Expected the failure to propagate")
        } catch {
            // expected
        }
    }

    // MARK: - Empty / boundary

    func test_givenEmptyCatalogue_whenFetching_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "events": [] }"#)
        let service = NotificationPreferencesService(api: api)

        let events = try await service.catalogue()

        XCTAssertTrue(events.isEmpty)
    }
}
