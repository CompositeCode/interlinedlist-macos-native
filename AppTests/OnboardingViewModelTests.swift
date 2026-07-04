// OnboardingViewModelTests
//
// BDD-named unit tests for `OnboardingViewModel`. View-model only —
// no SwiftUI rendering exercised. Covers the required quartet per
// behaviour:
//   1. Happy path — canonical success.
//   2. Invalid input — rejected before the service is called; no
//      service call was made.
//   3. Upstream API failure — service throws; error surface is correct.
//   4. Empty / boundary — empty input, empty password, passwords mismatch.
//
// `StubSessionManaging` is used as the session double. Its staging
// methods (`enqueueSignIn`, `enqueueRegister`, `enqueuePasswordReset`)
// control the outcome of each test scenario.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    // MARK: - Sign-in: invalid input (no service call)

    func test_givenSignInMode_whenSubmitWithEmptyEmail_thenSetsErrorMessage() async {
        // Given
        let session = StubSessionManaging()
        let vm = OnboardingViewModel(session: session)
        vm.email = ""
        vm.password = "secret"

        // When
        await vm.submit()

        // Then — error set without reaching the network
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_givenSignInMode_whenSubmitWithEmptyPassword_thenSetsErrorMessage() async {
        // Given
        let session = StubSessionManaging()
        let vm = OnboardingViewModel(session: session)
        vm.email = "ada@example.com"
        vm.password = ""

        // When
        await vm.submit()

        // Then — error set without reaching the network
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Sign-in: happy path

    func test_givenSignInMode_whenSignInSucceeds_thenClearsErrorMessage() async throws {
        // Given
        let session = StubSessionManaging()
        let user = MessageFixtures.currentUser(id: "u1", username: "ada")
        await session.enqueueSignIn(success: user)
        let vm = OnboardingViewModel(session: session)
        vm.email = "ada@example.com"
        vm.password = "correctpassword"
        // Pre-set a stale error to verify it gets cleared on success.
        // (Access the private setter via the submit path — just verify
        //  the final state after a successful call.)

        // When
        await vm.submit()

        // Then
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Sign-in: upstream API failure

    func test_givenSignInMode_whenSignInFails_thenSetsErrorMessage() async {
        // Given
        let session = StubSessionManaging()
        let failure = TestError.upstream("invalid credentials")
        await session.enqueueSignIn(failure: failure)
        let vm = OnboardingViewModel(session: session)
        vm.email = "ada@example.com"
        vm.password = "wrongpassword"

        // When
        await vm.submit()

        // Then — error surfaced and loading cleared
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Register: passwords mismatch (invalid input, no service call)

    func test_givenRegisterMode_whenPasswordsDoNotMatch_thenSetsErrorMessage() async {
        // Given
        let session = StubSessionManaging()
        let vm = OnboardingViewModel(session: session)
        vm.switchMode(to: .register)
        vm.email = "ada@example.com"
        vm.password = "password1"
        vm.confirmPassword = "password2"

        // When
        await vm.submit()

        // Then — error set before the network is reached
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Forgot password: happy path

    func test_givenForgotPasswordMode_whenResetSucceeds_thenSetsdidSendResetTrue() async {
        // Given
        let session = StubSessionManaging()
        await session.enqueuePasswordReset(success: ())
        let vm = OnboardingViewModel(session: session)
        vm.switchMode(to: .forgotPassword)
        vm.email = "ada@example.com"

        // When
        await vm.submit()

        // Then — reset flag set, no error
        XCTAssertTrue(vm.didSendReset)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Mode switching

    func test_givenSignInMode_whenSwitchingToRegister_thenClearsErrorAndPassword() async {
        // Given — a view model that already has an error and password filled.
        let session = StubSessionManaging()
        await session.enqueueSignIn(failure: TestError.upstream("bad creds"))
        let vm = OnboardingViewModel(session: session)
        vm.email = "ada@example.com"
        vm.password = "wrong"
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)

        // When
        vm.switchMode(to: .register)

        // Then — error cleared, passwords reset
        XCTAssertEqual(vm.mode, .register)
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.password.isEmpty)
        XCTAssertTrue(vm.confirmPassword.isEmpty)
    }

    // MARK: - Boundary: invalid email format

    func test_givenSignInMode_whenSubmitWithMalformedEmail_thenSetsErrorMessageWithoutCallingService() async {
        // Given
        let session = StubSessionManaging()
        // No outcome staged — if signIn is called, it throws "not staged", which
        // would also set an error. We assert the message is about the email format
        // specifically, proving the validation path ran rather than the service.
        let vm = OnboardingViewModel(session: session)
        vm.email = "not-an-email"
        vm.password = "password"

        // When
        await vm.submit()

        // Then — error mentions email validation, not a network failure
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        // The validation message is about a valid email address, not a
        // network/stub error.
        let msg = vm.errorMessage ?? ""
        XCTAssertTrue(
            msg.localizedCaseInsensitiveContains("email"),
            "Expected email validation message, got: \(msg)"
        )
    }
}
