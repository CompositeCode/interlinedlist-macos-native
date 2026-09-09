import XCTest
@testable import InterlinedDomain

/// Coverage for the resend-verification-email affordance (GitHub #41).
///
/// The route itself is `x-auth-type: session` and unreachable from this Bearer
/// client, so what is modelled here is the cooldown that decides whether the
/// deep-link action is offered or disabled.
final class EmailVerificationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Happy path

    func test_givenNoPriorResend_whenAskingAvailability_thenImmediatelyAvailable() {
        // Given — a fresh install, nothing sent yet.
        let resend = EmailVerificationResend()

        // Then
        XCTAssertTrue(resend.isAvailable(now: now))
        XCTAssertEqual(resend.remainingCooldown(now: now), 0)
        XCTAssertNil(resend.availableAt(now: now))
    }

    func test_givenResendRecorded_whenAskingImmediatelyAfter_thenFullCooldownRemains() {
        // Given
        let resend = EmailVerificationResend().recordingResend(at: now)

        // Then — the documented ten minutes.
        XCTAssertFalse(resend.isAvailable(now: now))
        XCTAssertEqual(resend.remainingCooldown(now: now), 600)
        XCTAssertEqual(resend.availableAt(now: now), now.addingTimeInterval(600))
    }

    // MARK: - Invalid input

    func test_givenResendTimestampInTheFuture_whenAskingCooldown_thenClampedNotNegative() {
        // Given — a clock change, or state restored from a device whose clock
        // has since moved backwards.
        let resend = EmailVerificationResend(lastResendAt: now.addingTimeInterval(3_600))

        // Then — a finite, sane wait rather than a negative or runaway value.
        let remaining = resend.remainingCooldown(now: now)
        XCTAssertGreaterThanOrEqual(remaining, 0)
        XCTAssertLessThanOrEqual(remaining, EmailVerificationResend.cooldown)
        XCTAssertFalse(resend.isAvailable(now: now))
    }

    // MARK: - Upstream failure

    /// The route is session-only, so the client must send the user to the web
    /// page that has a session rather than calling an endpoint that would 401.
    func test_givenResendRequested_whenBuildingAction_thenDeepLinksToWebSettings() {
        let resend = EmailVerificationResend()

        let url = resend.resendURL()

        XCTAssertEqual(url.absoluteString, "https://interlinedlist.com/settings")
    }

    func test_givenCustomBaseURL_whenBuildingResendURL_thenHonoursIt() {
        // Staging / self-hosted origins must not be hardcoded past.
        let resend = EmailVerificationResend()

        let url = resend.resendURL(baseURL: URL(string: "https://staging.example.com")!)

        XCTAssertEqual(url.absoluteString, "https://staging.example.com/settings")
    }

    // MARK: - Boundary: the ten-minute edge

    func test_givenCooldownJustUnderTenMinutes_whenAskingAvailability_thenStillBlocked() {
        // Given — one second short of the limit.
        let resend = EmailVerificationResend(lastResendAt: now.addingTimeInterval(-599))

        // Then
        XCTAssertFalse(resend.isAvailable(now: now))
        XCTAssertEqual(resend.remainingCooldown(now: now), 1, accuracy: 0.001)
    }

    func test_givenCooldownExactlyTenMinutes_whenAskingAvailability_thenAvailable() {
        // Given — exactly at the boundary, which must resolve in the user's favour.
        let resend = EmailVerificationResend(lastResendAt: now.addingTimeInterval(-600))

        // Then
        XCTAssertTrue(resend.isAvailable(now: now))
        XCTAssertEqual(resend.remainingCooldown(now: now), 0)
    }

    func test_givenCooldownJustOverTenMinutes_whenAskingAvailability_thenAvailable() {
        let resend = EmailVerificationResend(lastResendAt: now.addingTimeInterval(-601))

        XCTAssertTrue(resend.isAvailable(now: now))
        XCTAssertNil(resend.availableAt(now: now))
    }

    // MARK: - Web destinations

    func test_givenEachDestination_whenBuildingURL_thenMatchesTheLivePaths() {
        // Verified live 2026-09-09; `/contact` is deliberately absent (404).
        XCTAssertEqual(AccountWebDestination.settings.url().absoluteString, "https://interlinedlist.com/settings")
        XCTAssertEqual(AccountWebDestination.support.url().absoluteString, "https://interlinedlist.com/support")
        XCTAssertEqual(AccountWebDestination.help.url().absoluteString, "https://interlinedlist.com/help")
    }

    func test_givenEachRemedy_whenAskingDestination_thenRoutesToTheRightPage() {
        XCTAssertEqual(CapabilityRemedy.verifyEmail.webDestination, .settings)
        XCTAssertEqual(CapabilityRemedy.contactSupport.webDestination, .support)
        XCTAssertEqual(CapabilityRemedy.upgrade(.listCreation).webDestination, .settings)
    }

    /// A closed account has no next step, so the UI must not render a button
    /// that goes nowhere.
    func test_givenNoRemedy_whenAskingDestination_thenNil() {
        XCTAssertNil(CapabilityRemedy.noneAvailable.webDestination)
    }
}
