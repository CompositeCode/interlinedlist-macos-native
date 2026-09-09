import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the service-side wiring of the account's View
/// Preferences (work-consolidation.md G35 / issue #43):
///
/// - the `.followers` timeline scope short-circuits like `.following`, because
///   the API has no follower feed (re-verified live 2026-09-09);
/// - `NotificationsService.tray(limit:)` sends *and* enforces the account's
///   notification tray limit;
/// - `UserService.setShowAdvancedPostSettings` writes exactly one field, which
///   is what lets the composer's gear persist without carrying a stale
///   settings snapshot.
final class ViewPreferencesWiringTests: XCTestCase {

    // MARK: - Timeline: .followers scope (App Store — Coming Soon gating)

    func test_givenFollowersScope_whenLoadingTimeline_thenReturnsEmptyPageWithoutAPICall() async throws {
        // Given — nothing enqueued: any accidental API call makes the stub throw.
        let api = StubAPIClient()
        let service = MessagesService(api: api)

        // When
        let page = try await service.timeline(scope: .followers, tag: nil, limit: 20, offset: 0)

        // Then — empty page, and the network was never touched. Sending the
        // request would return the *unfiltered* timeline under a "Followers"
        // label, which is worse than an honest empty state.
        XCTAssertTrue(page.messages.isEmpty)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "No API request must be made for the .followers scope")
    }

    func test_givenFollowersScopeWithStore_whenLoadingTimeline_thenCacheIsNotWritten() async throws {
        // Boundary: a wired cache must not be poisoned with an empty page,
        // which would then be served as a "cached" result to the real feeds.
        let api = StubAPIClient()
        let store = InMemoryMessageStore()
        let service = MessagesService(api: api, store: store)

        _ = try await service.timeline(scope: .followers, tag: nil, limit: 20, offset: 0)

        let cached = await store.cachedTimeline(scope: .followers, tag: nil)
        XCTAssertTrue(cached.isEmpty)
    }

    func test_givenServedScope_whenLoadingTimeline_thenStillCallsTheAPI() async throws {
        // Guard against the short-circuit widening: `.all` must keep fetching.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedMessages(ids: ["m-1"]))
        let service = MessagesService(api: api)

        _ = try await service.timeline(scope: .all, tag: nil, limit: 20, offset: 0)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/messages")
    }

    // MARK: - Notification tray limit

    func test_givenTrayLimit_whenLoadingTray_thenSendsItAndTrimsTheRenderedRows() async throws {
        // Given — the server returns more rows than the account's limit. Under
        // `scope=tray` it ignores the query parameter (probed 2026-09-09), so
        // the client-side cap is what makes the preference observable.
        let api = StubAPIClient()
        let items = (1...5).map { Fixtures.notificationObject(id: "n-\($0)") }
        await api.enqueue(json: Fixtures.notificationTrayEnvelope(unreadCount: 4, items: items))
        let service = NotificationsService(api: api)

        // When
        let tray = try await service.tray(limit: 2)

        // Then — trimmed rows, untouched unread count, and the limit on the wire.
        XCTAssertEqual(tray.items.map(\.id), ["n-1", "n-2"])
        XCTAssertEqual(
            tray.unreadCount,
            4,
            "The server-authoritative unread badge must not be understated by trimming rows"
        )
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.query["scope"], "tray")
        XCTAssertEqual(recorded.first?.query["limit"], "2")
    }

    func test_givenNoTrayLimit_whenLoadingTray_thenOmitsTheParameterAndKeepsEveryRow() async throws {
        // Boundary: `nil` leaves the page size entirely to the server, which
        // applies the account's own `notificationTrayLimit`.
        let api = StubAPIClient()
        let items = (1...3).map { Fixtures.notificationObject(id: "n-\($0)") }
        await api.enqueue(json: Fixtures.notificationTrayEnvelope(unreadCount: 3, items: items))
        let service = NotificationsService(api: api)

        let tray = try await service.tray(limit: nil)

        XCTAssertEqual(tray.items.count, 3)
        let recorded = await api.recorded
        XCTAssertNil(recorded.first?.query["limit"])
    }

    func test_givenFewerRowsThanTheLimit_whenLoadingTray_thenReturnsThemAllUntouched() async throws {
        // Boundary: the cap must never pad, and must be a no-op below the limit.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.notificationTrayEnvelope(
            unreadCount: 1,
            items: [Fixtures.notificationObject(id: "n-1")]
        ))
        let service = NotificationsService(api: api)

        let tray = try await service.tray(limit: 40)

        XCTAssertEqual(tray.items.map(\.id), ["n-1"])
    }

    func test_givenTrayEndpointFails_whenLoadingTrayWithLimit_thenPropagatesTheError() async throws {
        // Upstream failure: the cap must not swallow an error into an empty tray.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 503, serverMessage: "down"))
        let service = NotificationsService(api: api)

        do {
            _ = try await service.tray(limit: 20)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 503, serverMessage: "down"))
        }
    }

    // MARK: - Single-field advanced-post-settings write (composer gear)

    func test_givenGearToggle_whenPersisting_thenPatchesOnlyThatFieldAndReturnsServerTruth() async throws {
        // Given — the server echoes the account with the preference now on.
        let api = StubAPIClient()
        await api.enqueue(json: """
        {
          "message": "User updated successfully",
          "user": {
            "id": "u1", "email": "ada@example.com", "username": "ada",
            "emailVerified": true, "customerStatus": "subscriber",
            "showAdvancedPostSettings": true, "messagesPerPage": 20,
            "viewingPreference": "all_messages", "notificationTrayLimit": 20,
            "createdAt": "2026-01-01T00:00:00.000Z"
          }
        }
        """)
        let service = UserService(api: api)

        // When
        let updated = try await service.setShowAdvancedPostSettings(true)

        // Then — the caller gets the server's authoritative view…
        XCTAssertTrue(updated.showAdvancedPostSettings)
        // …and the request went to the verified PATCH route.
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
        XCTAssertEqual(recorded.first?.path, "/api/user/update")
    }

    func test_givenSingleFieldWrite_whenBuildingTheBody_thenEveryOtherKeyIsOmitted() throws {
        // Invalid-by-omission guard: `UpdateUserRequest` drops nil fields, so a
        // one-field write can never clobber a page size or viewing preference
        // set moments earlier in Settings.
        let body = UpdateUserRequest(showAdvancedPostSettings: false)

        let data = try JSONEncoder().encode(body)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(Array(object.keys), ["showAdvancedPostSettings"])
        XCTAssertEqual(object["showAdvancedPostSettings"] as? Bool, false)
    }

    func test_givenUpdateFails_whenPersistingTheGear_thenThrows() async throws {
        // Upstream failure: the composer relies on this throwing to roll its
        // optimistic flip back.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = UserService(api: api)

        do {
            _ = try await service.setShowAdvancedPostSettings(true)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }
}
