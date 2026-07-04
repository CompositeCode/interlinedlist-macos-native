// AccountViewModelTests
//
// BDD-named tests for the M7 Settings > Account view model.
// Quartet per public method: happy + invalid input + upstream API
// failure + empty/boundary.
//
// Tests view-model logic only — no SwiftUI rendering per the
// project's view-layer rule.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class AccountViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(
        currentUser: CurrentUser? = nil
    ) async throws -> (AccountViewModel, StubUserService, StubSessionManaging, CurrentUserStore) {
        let userService = StubUserService()
        let session = StubSessionManaging()
        let store = CurrentUserStore(session: session)
        if let user = currentUser {
            await session.enqueueRestore(success: .signedIn(user))
            _ = try await store.restore()
        }
        let vm = AccountViewModel(
            userService: userService,
            session: session,
            currentUserStore: store
        )
        return (vm, userService, session, store)
    }

    // MARK: - requestEmailChange — invalid input (no service call)

    func test_givenEmptyNewEmail_whenRequestEmailChange_thenSetsErrorMessage() async throws {
        // Given
        let (vm, userService, _, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        vm.newEmail = "   "

        // When
        await vm.requestEmailChange()

        // Then — error set, no service call made.
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.emailChangeSuccess)
        XCTAssertTrue(
            userService.recorded.filter {
                if case .requestEmailChange = $0.kind { return true }
                return false
            }.isEmpty,
            "No service call should be made for an empty email"
        )
    }

    func test_givenSameEmail_whenRequestEmailChange_thenSetsErrorMessage() async throws {
        // Given — invalid input: user types the same address they already have.
        let user = MessageFixtures.currentUser(id: "u1", username: "ada")
        // MessageFixtures.currentUser builds email as "<username>@example.com"
        let (vm, userService, _, _) = try await makeViewModel(currentUser: user)
        vm.newEmail = user.email   // "ada@example.com"

        // When
        await vm.requestEmailChange()

        // Then — rejected before network; no service call.
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.emailChangeSuccess)
        XCTAssertTrue(
            userService.recorded.filter {
                if case .requestEmailChange = $0.kind { return true }
                return false
            }.isEmpty,
            "No service call should be made when email is unchanged"
        )
    }

    // MARK: - requestEmailChange — happy path

    func test_givenValidEmail_whenRequestEmailChangeSucceeds_thenSetsEmailChangeSuccessTrue() async throws {
        // Given — a valid new address different from the current one.
        let (vm, userService, _, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        vm.newEmail = "ada.new@example.com"
        userService.enqueueRequestEmailChange()

        // When
        await vm.requestEmailChange()

        // Then
        XCTAssertTrue(vm.emailChangeSuccess)
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.newEmail.isEmpty, "newEmail cleared after successful send")
    }

    // MARK: - requestEmailChange — upstream API failure

    func test_givenValidEmail_whenRequestEmailChangeFails_thenSetsErrorMessage() async throws {
        // Given — service throws on the network call.
        let (vm, userService, _, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        vm.newEmail = "ada.new@example.com"
        userService.enqueueRequestEmailChange(failure: TestError.upstream("server error"))

        // When
        await vm.requestEmailChange()

        // Then — success flag not set; error surfaced.
        XCTAssertFalse(vm.emailChangeSuccess)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - requestEmailChange — boundary (no-@-format)

    func test_givenMalformedEmail_whenRequestEmailChange_thenSetsErrorMessage() async throws {
        // Given — boundary: no `@` in the address.
        let (vm, userService, _, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        vm.newEmail = "notanemail"

        // When
        await vm.requestEmailChange()

        // Then — rejected before network.
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(
            userService.recorded.filter {
                if case .requestEmailChange = $0.kind { return true }
                return false
            }.isEmpty
        )
    }

    // MARK: - deleteAccount — happy path

    func test_givenDeleteAccount_whenServiceSucceeds_thenCallsSignOut() async throws {
        // Given
        let (vm, userService, session, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        vm.confirmDeletePassword = "s3cr3t"
        userService.enqueueDeleteAccount()

        // When
        await vm.deleteAccount()

        // Then — session is signed out after successful deletion.
        let state = await session.currentState()
        XCTAssertEqual(state, .signedOut)
        XCTAssertNil(vm.errorMessage)
        // confirmDeletePassword cleared on completion.
        XCTAssertTrue(vm.confirmDeletePassword.isEmpty)
    }

    // MARK: - deleteAccount — upstream API failure (rollback / no sign-out)

    func test_givenDeleteAccount_whenServiceFails_thenSetsErrorMessageAndDoesNotSignOut() async throws {
        // Given — wrong password rejected by server.
        let (vm, userService, session, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        vm.confirmDeletePassword = "wrong"
        userService.enqueueDeleteAccount(failure: TestError.upstream("incorrect password"))

        // When
        await vm.deleteAccount()

        // Then — error surfaced; session unchanged (still signed in — signOut() was not called).
        XCTAssertNotNil(vm.errorMessage)
        let state = await session.currentState()
        XCTAssertEqual(state, .signedIn(MessageFixtures.currentUser(id: "u1", username: "ada")))
    }

    // MARK: - signOut — happy path

    func test_givenSignedIn_whenSignOut_thenSessionIsSignedOut() async throws {
        // Given — no staging needed; stub signOut() succeeds by default.
        let (vm, _, session, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )

        // When
        await vm.signOut()

        // Then — session is cleared; no error surfaced.
        let state = await session.currentState()
        XCTAssertEqual(state, .signedOut)
        XCTAssertNil(vm.errorMessage)
    }

    func test_givenSignedIn_whenSignOutFails_thenSetsErrorMessage() async throws {
        // Given — server rejects the sign-out request.
        let (vm, _, session, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        await session.enqueueSignOut(failure: TestError.upstream("session already expired"))

        // When
        await vm.signOut()

        // Then — error surfaced; session state unchanged.
        XCTAssertNotNil(vm.errorMessage)
        let state = await session.currentState()
        XCTAssertEqual(state, .signedIn(MessageFixtures.currentUser(id: "u1", username: "ada")))
    }

    // MARK: - pickAndUploadAvatar — happy path

    func test_givenImageData_whenPickAndUploadAvatarSucceeds_thenNoError() async throws {
        // Given
        let (vm, userService, session, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        let avatarURL = URL(string: "https://cdn.example.com/avatar.png")!
        userService.enqueueUploadAvatar(success: avatarURL)
        // restore() after avatar upload will use the session state.
        await session.enqueueRestore(success: .signedIn(MessageFixtures.currentUser(id: "u1", username: "ada")))

        // When
        await vm.pickAndUploadAvatar(data: Data([0xFF, 0xD8]), contentType: "image/jpeg")

        // Then — no error; upload was recorded.
        XCTAssertNil(vm.errorMessage)
        let calls = userService.recorded
        XCTAssertTrue(calls.contains { $0.kind == .uploadAvatar(contentType: "image/jpeg") })
    }

    // MARK: - pickAndUploadAvatar — upstream failure

    func test_givenImageData_whenPickAndUploadAvatarFails_thenSetsErrorMessage() async throws {
        // Given
        let (vm, userService, _, _) = try await makeViewModel(
            currentUser: MessageFixtures.currentUser(id: "u1", username: "ada")
        )
        userService.enqueueUploadAvatar(failure: TestError.upstream("413 payload too large"))

        // When
        await vm.pickAndUploadAvatar(data: Data([0xFF]), contentType: "image/jpeg")

        // Then
        XCTAssertNotNil(vm.errorMessage)
    }
}
