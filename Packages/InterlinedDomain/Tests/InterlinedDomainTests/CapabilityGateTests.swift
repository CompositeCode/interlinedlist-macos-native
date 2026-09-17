import XCTest
@testable import InterlinedDomain

/// Coverage for the composed capability gate (GitHub #40 / #41 / #42).
///
/// The three mechanisms — account status, email verification, subscription
/// tier — are independent, and an account can fail several at once. These cases
/// pin the precedence, because the precedence is what decides whether the user
/// is told something they can act on.
final class CapabilityGateTests: XCTestCase {

    // MARK: - Happy path

    func test_givenActiveVerifiedSubscriber_whenEvaluatingEveryAction_thenAllAllowed() {
        // Given — the fully unencumbered account.
        let gate = makeGate(status: .active, tier: .subscriber, verified: true)

        // Then — nothing is gated, for any action.
        for action in GatedAction.allCases {
            XCTAssertEqual(gate.evaluate(action), .allowed, "\(action) should be allowed")
        }
    }

    func test_givenActiveVerifiedFreeAccount_whenPosting_thenAllowed() {
        // Posting is free on every tier — the gate must not invent a paywall.
        let gate = makeGate(status: .active, tier: .free, verified: true)

        XCTAssertTrue(gate.allows(.postMessage))
        XCTAssertTrue(gate.allows(.reactToMessage))
        XCTAssertTrue(gate.allows(.followUser))
        XCTAssertTrue(gate.allows(.directMessages))
    }

    // MARK: - Invalid state: restricted account

    func test_givenRestrictedAccount_whenEvaluatingWrites_thenDeniedAsReadOnlyAndReadsUnaffected() {
        // Given — a *subscriber* under review, to prove status outranks tier.
        let gate = makeGate(status: .restricted, tier: .subscriber, verified: true)

        // Then — the documented blocked set is denied with the read-only reason.
        XCTAssertEqual(gate.evaluate(.postMessage), .denied(.accountReadOnly(.restricted)))
        XCTAssertEqual(gate.evaluate(.replyToMessage), .denied(.accountReadOnly(.restricted)))
        XCTAssertEqual(gate.evaluate(.reactToMessage), .denied(.accountReadOnly(.restricted)))
        XCTAssertEqual(gate.evaluate(.followUser), .denied(.accountReadOnly(.restricted)))
        XCTAssertEqual(gate.evaluate(.directMessages), .denied(.accountReadOnly(.restricted)))
        XCTAssertEqual(gate.evaluate(.listCreation), .denied(.accountReadOnly(.restricted)))
    }

    func test_givenSuspendedAccount_whenEvaluatingWrites_thenDenialCarriesTheSuspendedStatus() {
        // The UI distinguishes "under review" from "actioned by the team", so
        // the denial must carry which one it is.
        let gate = makeGate(status: .suspended, tier: .free, verified: true)

        XCTAssertEqual(gate.evaluate(.postMessage), .denied(.accountReadOnly(.suspended)))
    }

    func test_givenRestrictedSubscriber_whenPosting_thenStatusOutranksSubscription() {
        // The precedence rule stated in #42: "a subscriber who is restricted
        // still cannot post". Paying must not buy past a review.
        let gate = makeGate(status: .restricted, tier: .subscriber, verified: true)

        XCTAssertEqual(gate.denial(for: .mediaAttachments), .accountReadOnly(.restricted))
    }

    // MARK: - Upstream failure: unknown / absent status

    /// The fail-open guarantee, end to end: a status string the client has
    /// never seen must disable nothing.
    func test_givenUnknownAccountStatus_whenEvaluatingEveryAction_thenNothingIsDisabledByStatus() {
        let gate = makeGate(status: .unknown("quarantined"), tier: .subscriber, verified: true)

        for action in GatedAction.allCases {
            XCTAssertEqual(gate.evaluate(action), .allowed, "\(action) must not be gated by an unknown status")
        }
    }

    func test_givenAbsentStatusFromServer_whenBuildingGate_thenTreatedAsActive() {
        // A payload with no `accountStatus` at all.
        let user = makeUser(accountStatus: AccountStatus(raw: nil), tier: .subscriber, verified: true)
        let gate = CapabilityGate(user: user)

        XCTAssertEqual(gate.accountStatus, .active)
        XCTAssertTrue(gate.allows(.postMessage))
    }

    func test_givenSignedOutUser_whenBuildingGate_thenFreeAndUnverifiedButNotRestricted() {
        // Given — nobody signed in.
        let gate = CapabilityGate(user: nil)

        // Then — the gate must not invent a restriction for an unknown account,
        // but it also must not hand out subscriber features.
        XCTAssertEqual(gate.accountStatus, .active)
        XCTAssertFalse(gate.isEmailVerified)
        XCTAssertEqual(gate.denial(for: .listCreation), .subscriberRequired(.listCreation))
    }

    // MARK: - Boundary: the `new` account

    /// The most nuanced case in #42: plain posting stays enabled (it is
    /// rate-limited, not blocked) while a specific documented set is locked.
    func test_givenNewAccount_whenEvaluatingActions_thenOnlyTheDocumentedSetIsLocked() {
        // Given — verified so the email gate cannot confound the result, and a
        // subscriber so the tier gate cannot either.
        let gate = makeGate(status: .new, tier: .subscriber, verified: true)

        // Then — plain posting and social reads/writes stay available.
        XCTAssertTrue(gate.allows(.postMessage), "Posting is rate-limited on a new account, not blocked")
        XCTAssertTrue(gate.allows(.replyToMessage))
        XCTAssertTrue(gate.allows(.reactToMessage))
        XCTAssertTrue(gate.allows(.followUser))

        // And the documented locked set is denied, with the probation reason.
        let locked: [GatedAction] = [
            .directMessages, .directMessageImages, .mediaAttachments,
            .crossPosting, .scheduledPosts,
            .listCreation,
            .documentCreation, .documentTemplateCreation, .organizationCreation,
        ]
        for action in locked {
            XCTAssertEqual(gate.evaluate(action), .denied(.newAccountLocked), "\(action) is locked on probation")
        }
    }

    func test_givenBannedAccount_whenEvaluatingAnyAction_thenDeniedAsBanned() {
        // Reachable only in theory — a banned account cannot sign in — but the
        // model stays total so no call site has to handle a missing case.
        let gate = makeGate(status: .banned, tier: .subscriber, verified: true)

        XCTAssertEqual(gate.evaluate(.postMessage), .denied(.accountBanned))
        XCTAssertEqual(gate.evaluate(.aiFeatures), .denied(.accountBanned))
    }

    // MARK: - Email verification (GitHub #41)

    func test_givenUnverifiedEmail_whenPosting_thenDeniedForVerification() {
        let gate = makeGate(status: .active, tier: .subscriber, verified: false)

        XCTAssertEqual(gate.evaluate(.postMessage), .denied(.emailUnverified))
        XCTAssertEqual(gate.evaluate(.replyToMessage), .denied(.emailUnverified))
        XCTAssertEqual(gate.evaluate(.mediaAttachments), .denied(.emailUnverified))
        XCTAssertEqual(gate.evaluate(.directMessageImages), .denied(.emailUnverified))
    }

    func test_givenUnverifiedEmail_whenDoingActionsThatDoNotRequireIt_thenAllowed() {
        // Only posting and media are documented as verification-gated; the gate
        // must not over-reach and lock an unverified user out of the whole app.
        let gate = makeGate(status: .active, tier: .subscriber, verified: false)

        XCTAssertTrue(gate.allows(.reactToMessage))
        XCTAssertTrue(gate.allows(.followUser))
        XCTAssertTrue(gate.allows(.directMessages), "A text-only DM is not verification-gated")
        XCTAssertTrue(gate.allows(.listCreation))
    }

    /// Precedence between the two "you cannot post" reasons. A new, unverified
    /// account is told to verify — which is both the cheaper fix and the
    /// documented fastest way off probation — not that it is on probation.
    func test_givenNewUnverifiedAccount_whenPosting_thenVerificationIsTheReasonGiven() {
        let gate = makeGate(status: .new, tier: .free, verified: false)

        XCTAssertEqual(gate.evaluate(.postMessage), .denied(.emailUnverified))
    }

    // MARK: - Subscription tier (GitHub #40)

    func test_givenFreeAccount_whenCreatingContent_thenDeniedWithNamedFeature() {
        let gate = makeGate(status: .active, tier: .free, verified: true)

        // The denial names the feature so the upgrade prompt can be specific.
        XCTAssertEqual(gate.evaluate(.listCreation), .denied(.subscriberRequired(.listCreation)))
        XCTAssertEqual(gate.evaluate(.documentCreation), .denied(.subscriberRequired(.documentCreation)))
        XCTAssertEqual(gate.evaluate(.organizationCreation), .denied(.subscriberRequired(.organizationCreation)))
        XCTAssertEqual(gate.evaluate(.shareLinkCreation), .denied(.subscriberRequired(.shareLinkCreation)))
        XCTAssertEqual(gate.evaluate(.aiFeatures), .denied(.subscriberRequired(.aiFeatures)))
    }

    /// The lapsed-subscriber boundary from #40: the tier gate covers creation
    /// only, so nothing a lapsed user does to *existing* content is modelled as
    /// a gated action in the first place.
    func test_givenLapsedSubscriber_whenActingOnExistingContent_thenNoGatedActionCoversIt() {
        let gate = makeGate(status: .active, tier: .free, verified: true)

        // Creation is denied …
        XCTAssertFalse(gate.allows(.listCreation))
        // … while every free action stays available.
        XCTAssertTrue(gate.allows(.postMessage))
        XCTAssertTrue(gate.allows(.followUser))

        // And no `GatedAction` exists for editing, row-adding, revoking, or
        // removing access — the vocabulary itself prevents gating them.
        let creationOnly = GatedAction.allCases.filter { $0.requiredFeature != nil }
        for action in creationOnly {
            XCTAssertFalse(
                "\(action)".contains("edit") || "\(action)".contains("revoke") || "\(action)".contains("remove"),
                "\(action) names a non-create operation, which must never be tier-gated"
            )
        }
    }

    func test_givenUnknownCustomerStatus_whenCreating_thenFailsClosedForCreation() {
        // #40: an unrecognised tier must not hand out paid features.
        let gate = makeGate(status: .active, tier: .other("trialing"), verified: true)

        XCTAssertEqual(gate.evaluate(.documentCreation), .denied(.subscriberRequired(.documentCreation)))
        // But it must still leave the free surface alone.
        XCTAssertTrue(gate.allows(.postMessage))
    }

    // MARK: - Action metadata invariants

    /// Actions with no subscriber dimension are exactly the ones the published
    /// Free tier names. A drift here silently paywalls something free.
    func test_givenActionsWithoutFeature_whenListed_thenTheyAreTheDocumentedFreeSet() {
        let free = Set(GatedAction.allCases.filter { $0.requiredFeature == nil })
        XCTAssertEqual(
            free,
            [.postMessage, .replyToMessage, .reactToMessage, .followUser, .directMessages, .directMessageImages]
        )
    }

    // MARK: - Denial copy and remedy

    func test_givenEveryDenial_whenAskingForCopy_thenMessageIsPresent() {
        let denials: [CapabilityDenial] = [
            .accountBanned, .accountReadOnly(.restricted), .accountReadOnly(.suspended),
            .newAccountLocked, .emailUnverified, .subscriberRequired(.listCreation),
        ]
        for denial in denials {
            XCTAssertFalse(denial.message.isEmpty, "\(denial) needs user-facing copy")
        }
    }

    /// Each denial must point at the step that actually resolves it, so the UI
    /// cannot offer "Upgrade" to someone whose real problem is a review.
    func test_givenEachDenial_whenAskingRemedy_thenPointsAtTheResolvingStep() {
        XCTAssertEqual(CapabilityDenial.emailUnverified.remedy, .verifyEmail)
        XCTAssertEqual(CapabilityDenial.newAccountLocked.remedy, .verifyEmail)
        XCTAssertEqual(CapabilityDenial.accountReadOnly(.restricted).remedy, .contactSupport)
        XCTAssertEqual(CapabilityDenial.accountReadOnly(.suspended).remedy, .contactSupport)
        XCTAssertEqual(CapabilityDenial.subscriberRequired(.aiFeatures).remedy, .upgrade(.aiFeatures))
        XCTAssertEqual(CapabilityDenial.accountBanned.remedy, .noneAvailable)
    }

    func test_givenSuspendedVersusRestricted_whenAskingCopy_thenWordingDiffers() {
        // The user is told which one applies to them; both are appealable.
        XCTAssertNotEqual(
            CapabilityDenial.accountReadOnly(.suspended).message,
            CapabilityDenial.accountReadOnly(.restricted).message
        )
    }

    /// The subscriber denial reuses the shared per-feature copy, so an upgrade
    /// prompt always names the thing the user just tried to do.
    func test_givenSubscriberDenial_whenAskingCopy_thenNamesTheFeature() {
        XCTAssertEqual(
            CapabilityDenial.subscriberRequired(.documentCreation).message,
            Feature.documentCreation.upgradeMessage
        )
    }

    // MARK: - Helpers

    private func makeGate(status: AccountStatus, tier: CustomerStatus, verified: Bool) -> CapabilityGate {
        CapabilityGate(
            accountStatus: status,
            entitlements: EntitlementsService(customerStatus: tier),
            isEmailVerified: verified
        )
    }

    private func makeUser(accountStatus: AccountStatus, tier: CustomerStatus, verified: Bool) -> CurrentUser {
        CurrentUser(
            summary: UserSummary(id: "1", username: "ada", displayName: "Ada"),
            email: "ada@example.com",
            customerStatus: tier,
            accountStatus: accountStatus,
            isEmailVerified: verified,
            isPrivateAccount: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
