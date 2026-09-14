// ComposerCapabilityGateTests
//
// The composer half of the "know why the server will say no" cluster
// (GitHub #40 / #41 / #42): the Post button and the media affordance must
// reflect account status, email verification, and subscription tier *before*
// the user does the work, not after a server error.
//
// View-model only — no SwiftUI rendering. Kept in its own file so the large
// existing `ComposerViewModelTests` suite stays untouched.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ComposerCapabilityGateTests: XCTestCase {

    // MARK: - Happy path

    func test_givenActiveVerifiedSubscriber_whenDrafting_thenPublishableWithNoExplanation() {
        // Given
        let viewModel = makeComposer(status: .active, tier: .subscriber, verified: true)
        viewModel.body = "hello"

        // Then
        XCTAssertTrue(viewModel.isPublishable)
        XCTAssertNil(viewModel.postDenial)
        XCTAssertNil(viewModel.postBlockedMessage)
    }

    func test_givenActiveVerifiedFreeAccount_whenDraftingPlainText_thenStillPublishable() {
        // Posting is free on every tier — the gate must not paywall a plain post.
        let viewModel = makeComposer(status: .active, tier: .free, verified: true)
        viewModel.body = "hello"

        XCTAssertTrue(viewModel.isPublishable)
        XCTAssertNil(viewModel.postBlockedMessage)
    }

    // MARK: - Invalid state: unverified email

    func test_givenUnverifiedEmail_whenDrafting_thenPostBlockedAndDraftPreserved() async {
        // Given — the exact scenario in #41: the user writes a whole message
        // before finding out.
        let stub = StubMessagesService()
        let viewModel = makeComposer(status: .active, tier: .subscriber, verified: false, messages: stub)
        viewModel.body = "a draft worth keeping"

        // Then — Post is refused up front, with an actionable reason …
        XCTAssertFalse(viewModel.isPublishable)
        XCTAssertEqual(viewModel.postDenial, .emailUnverified)
        XCTAssertEqual(viewModel.postBlockedRemedy, .verifyEmail)
        XCTAssertNotNil(viewModel.postBlockedMessage)

        // … and the draft survives: typing is never blocked.
        XCTAssertEqual(viewModel.body, "a draft worth keeping")

        // And nothing was sent.
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenUnverifiedEmail_whenAddingAttachment_thenBlockedWithVerificationReason() async {
        // Given
        let stub = StubMessagesService()
        let viewModel = makeComposer(status: .active, tier: .subscriber, verified: false, messages: stub)

        // When
        viewModel.addAttachments(urls: [URL(fileURLWithPath: "/tmp/test.png")])

        // Then — the reason is verification, not a subscription upsell: this
        // user is already paying, so an Upgrade prompt would be wrong.
        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertEqual(viewModel.error as? ComposerError, .blocked(.emailUnverified))
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - Upstream / account-state failure: restricted account

    func test_givenRestrictedSubscriber_whenDrafting_thenBlockedForReviewNotForPayment() async {
        // Given — a paying account under review. Status outranks tier.
        let stub = StubMessagesService()
        let viewModel = makeComposer(status: .restricted, tier: .subscriber, verified: true, messages: stub)
        viewModel.body = "hello"

        // Then
        XCTAssertFalse(viewModel.isPublishable)
        XCTAssertEqual(viewModel.postDenial, .accountReadOnly(.restricted))
        XCTAssertEqual(viewModel.postBlockedRemedy, .contactSupport)

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenSuspendedAccount_whenAddingAttachment_thenBlockedWithReadOnlyReason() {
        let viewModel = makeComposer(status: .suspended, tier: .subscriber, verified: true)

        viewModel.addAttachments(urls: [URL(fileURLWithPath: "/tmp/test.png")])

        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertEqual(viewModel.error as? ComposerError, .blocked(.accountReadOnly(.suspended)))
    }

    /// Fail-open, end to end through the view model: an unrecognised status
    /// must leave the composer exactly as permissive as an active one.
    func test_givenUnknownAccountStatus_whenDrafting_thenNothingIsBlocked() {
        let viewModel = makeComposer(status: .unknown("quarantined"), tier: .subscriber, verified: true)
        viewModel.body = "hello"

        XCTAssertTrue(viewModel.isPublishable)
        XCTAssertNil(viewModel.postBlockedMessage)
    }

    // MARK: - Boundary: the `new` account

    /// The nuance that makes #42 worth modelling: a new account *can* post
    /// (rate-limited) but *cannot* attach media. Disabling Post here would be
    /// as wrong as leaving media enabled.
    func test_givenNewVerifiedAccount_whenDrafting_thenCanPostButCannotAttachMedia() {
        // Given
        let viewModel = makeComposer(status: .new, tier: .subscriber, verified: true)
        viewModel.body = "my first post"

        // Then — posting stays available …
        XCTAssertTrue(viewModel.isPublishable)
        XCTAssertNil(viewModel.postBlockedMessage)

        // … while the documented locked set is refused.
        viewModel.addAttachments(urls: [URL(fileURLWithPath: "/tmp/test.png")])
        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertEqual(viewModel.error as? ComposerError, .blocked(.newAccountLocked))
    }

    /// A free account is still told about the tier, in the type the rest of the
    /// app already treats as a subscription lapse.
    func test_givenFreeAccount_whenAddingAttachment_thenSurfacesSubscriberRequired() {
        let viewModel = makeComposer(status: .active, tier: .free, verified: true)

        viewModel.addAttachments(urls: [URL(fileURLWithPath: "/tmp/test.png")])

        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertEqual(viewModel.error as? MessagesError, .subscriberRequired(.mediaAttachments))
    }

    /// Empty boundary: a blocked account with an empty body is unpublishable
    /// for both reasons, and must not crash or report a confusing one.
    func test_givenBlockedAccountAndEmptyBody_whenAskingPublishable_thenFalse() {
        let viewModel = makeComposer(status: .restricted, tier: .free, verified: false)
        viewModel.body = "   "

        XCTAssertFalse(viewModel.isPublishable)
        // Status is the hardest gate, so it is the reason reported.
        XCTAssertEqual(viewModel.postDenial, .accountReadOnly(.restricted))
    }

    // MARK: - Helpers

    private func makeComposer(
        status: AccountStatus,
        tier: CustomerStatus,
        verified: Bool,
        messages: StubMessagesService = StubMessagesService()
    ) -> ComposerViewModel {
        ComposerViewModel(
            messages: messages,
            eventBus: ComposerEventBus(),
            mode: .newPost,
            entitlements: EntitlementsService(customerStatus: tier),
            accountStatus: status,
            isEmailVerified: verified
        )
    }
}
