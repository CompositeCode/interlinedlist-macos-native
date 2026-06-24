// NotificationsPermissionCoordinatorTests
//
// BDD-named tests for the lazy UN-permission coordinator. Asserts:
//   - first visit: requests authorization and writes the asked flag.
//   - second visit: skips the request and returns the current
//     authorization state instead.
//   - failure path: a thrown error from the request is folded to
//     `false` so the caller surfaces a denied state, not an error.
//
// The test substitutes `NotificationsAuthorizationRequesting` so no
// real `UNUserNotificationCenter` is touched.

import XCTest
import UserNotifications
@testable import InterlinedList

@MainActor
final class NotificationsPermissionCoordinatorTests: XCTestCase {

    private let key = NotificationsPermissionCoordinator.askedKey

    private func makeDefaults() -> UserDefaults {
        let suiteName = "InterlinedList.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func test_givenFirstVisit_whenRequestingIfNeeded_thenCallsAuthorizationAndSetsAskedFlag() async {
        let center = StubAuthorization(grant: true, alreadyAuthorized: false)
        let defaults = makeDefaults()
        let coord = NotificationsPermissionCoordinator(center: center, defaults: defaults)

        let granted = await coord.requestIfNeeded()

        XCTAssertTrue(granted)
        XCTAssertTrue(defaults.bool(forKey: key))
        let count = await center.requestCount
        XCTAssertEqual(count, 1)
    }

    func test_givenAlreadyAsked_whenRequestingIfNeeded_thenSkipsRequestAndReadsSettings() async {
        let center = StubAuthorization(grant: false, alreadyAuthorized: true)
        let defaults = makeDefaults()
        defaults.set(true, forKey: key)
        let coord = NotificationsPermissionCoordinator(center: center, defaults: defaults)

        let authorized = await coord.requestIfNeeded()

        XCTAssertTrue(authorized)
        let count = await center.requestCount
        XCTAssertEqual(count, 0, "Already-asked must not re-prompt")
    }

    func test_givenAuthorizationThrows_whenRequestingIfNeeded_thenFoldsToFalse() async {
        let center = StubAuthorization(grant: false, alreadyAuthorized: false, throwOnRequest: true)
        let defaults = makeDefaults()
        let coord = NotificationsPermissionCoordinator(center: center, defaults: defaults)

        let granted = await coord.requestIfNeeded()

        XCTAssertFalse(granted)
        XCTAssertTrue(defaults.bool(forKey: key), "Even on failure the asked flag is set so we don't loop")
    }

    func test_givenAlreadyAskedAndDenied_whenRequestingIfNeeded_thenReturnsFalse() async {
        let center = StubAuthorization(grant: false, alreadyAuthorized: false)
        let defaults = makeDefaults()
        defaults.set(true, forKey: key)
        let coord = NotificationsPermissionCoordinator(center: center, defaults: defaults)

        let authorized = await coord.requestIfNeeded()

        XCTAssertFalse(authorized)
    }
}

// MARK: - Stub

private actor StubAuthorization: NotificationsAuthorizationRequesting {
    var requestCount = 0
    private let grant: Bool
    private let alreadyAuthorized: Bool
    private let throwOnRequest: Bool

    init(grant: Bool, alreadyAuthorized: Bool, throwOnRequest: Bool = false) {
        self.grant = grant
        self.alreadyAuthorized = alreadyAuthorized
        self.throwOnRequest = throwOnRequest
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestCount += 1
        if throwOnRequest {
            throw StubError.failed
        }
        return grant
    }

    func currentAuthorizationSettings() async -> NotificationsAuthorizationSettings {
        NotificationsAuthorizationSettings(isAuthorized: alreadyAuthorized)
    }

    enum StubError: Error { case failed }
}
