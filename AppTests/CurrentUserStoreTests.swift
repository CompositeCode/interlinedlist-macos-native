// CurrentUserStoreTests
//
// BDD-named tests for the App-layer session adapter. Covers the
// happy `restore` path, the failure path, the stream-driven update,
// and the empty / signed-out boundary.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class CurrentUserStoreTests: XCTestCase {

    func test_givenSignedInRestore_whenRestoring_thenCurrentUserIsPopulated() async throws {
        // Given
        let session = StubSessionManaging()
        let user = MessageFixtures.currentUser(id: "u1", username: "ada")
        await session.enqueueRestore(success: .signedIn(user))
        let store = CurrentUserStore(session: session)

        // When
        _ = try await store.restore()

        // Then
        XCTAssertEqual(store.currentUser?.id, "u1")
        XCTAssertEqual(store.currentUserID, "u1")
        XCTAssertEqual(store.currentUsername, "ada")
    }

    func test_givenRestoreFailure_whenRestoring_thenThrowsAndCurrentUserStaysNil() async {
        // Given — upstream API failure.
        let session = StubSessionManaging()
        let failure = TestError.upstream("network down")
        await session.enqueueRestore(failure: failure)
        let store = CurrentUserStore(session: session)

        // When / Then
        do {
            _ = try await store.restore()
            XCTFail("Expected a thrown error")
        } catch let error as TestError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertNil(store.currentUser)
    }

    func test_givenStreamYieldsSignedIn_whenStarted_thenCurrentUserMirrorsTheState() async throws {
        // Given
        let session = StubSessionManaging()
        let user = MessageFixtures.currentUser(id: "u9", username: "stream-user")
        let store = CurrentUserStore(session: session)
        store.start()

        // When — push a state through the stream and wait for the
        // store to apply it.
        await session.enqueueState(.signedIn(user))
        try await waitFor(condition: { store.currentUser?.id == "u9" })

        // Then
        XCTAssertEqual(store.currentUserID, "u9")
    }

    func test_givenNoStoredToken_whenRestoring_thenCurrentUserStaysNil() async throws {
        // Given — boundary: stubbed restore returns `.signedOut`.
        let session = StubSessionManaging()
        await session.enqueueRestore(success: .signedOut)
        let store = CurrentUserStore(session: session)

        // When
        _ = try await store.restore()

        // Then
        XCTAssertNil(store.currentUser)
        XCTAssertNil(store.currentUserID)
    }

    // MARK: - Helpers

    /// Polls `condition` until it returns `true` or 2 s elapses. Used
    /// when the assertion depends on a value arriving asynchronously
    /// from a stream we don't directly own a continuation on.
    private func waitFor(
        condition: @MainActor () -> Bool,
        timeout: Double = 2.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        XCTFail("Condition did not become true within \(timeout)s")
    }
}
