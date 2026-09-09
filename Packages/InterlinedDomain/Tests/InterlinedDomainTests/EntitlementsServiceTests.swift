import XCTest
@testable import InterlinedDomain

final class EntitlementsServiceTests: XCTestCase {

    // MARK: - Subscriber

    func test_givenSubscriber_whenCheckingFeatures_thenAllSubscriberFeaturesEnabled() {
        // Given
        let service = EntitlementsService(customerStatus: .subscriber)

        // When / Then
        XCTAssertTrue(service.isSubscriber)
        XCTAssertTrue(service.isEnabled(.mediaAttachments))
        XCTAssertTrue(service.isEnabled(.scheduledPosts))
        XCTAssertTrue(service.isEnabled(.crossPosting))
    }

    func test_givenSubscriberUser_whenConstructedFromUser_thenSubscriber() {
        // Given a subscriber CurrentUser
        let user = makeUser(status: .subscriber)
        let service = EntitlementsService(user: user)

        // Then
        XCTAssertTrue(service.isEnabled(.mediaAttachments))
    }

    // MARK: - Free / non-subscriber

    func test_givenFreeAccount_whenCheckingFeatures_thenAllSubscriberFeaturesDisabled() {
        // Given
        let service = EntitlementsService(customerStatus: .free)

        // When / Then
        XCTAssertFalse(service.isSubscriber)
        for feature in Feature.allCases {
            XCTAssertFalse(service.isEnabled(feature), "\(feature) should be gated for free accounts")
        }
    }

    func test_givenUnknownStatus_whenCheckingFeatures_thenTreatedAsNonSubscriber() {
        // Given an unrecognised status string.
        let service = EntitlementsService(customerStatus: .other("trialing"))

        // When / Then — unknown statuses must never unlock paid features.
        XCTAssertFalse(service.isSubscriber)
        XCTAssertFalse(service.isEnabled(.scheduledPosts))
    }

    // MARK: - Boundary: no user

    func test_givenNilUser_whenConstructed_thenNonSubscriber() {
        // Given a signed-out / unknown user.
        let service = EntitlementsService(user: nil)

        // When / Then
        XCTAssertFalse(service.isSubscriber)
        XCTAssertFalse(service.isEnabled(.crossPosting))
    }

    // MARK: - CustomerStatus mapping

    func test_givenVariousRawStatuses_whenMapped_thenClassifiedConsistently() {
        XCTAssertEqual(CustomerStatus(raw: "subscriber"), .subscriber)
        XCTAssertEqual(CustomerStatus(raw: "ACTIVE"), .subscriber)
        XCTAssertEqual(CustomerStatus(raw: "free"), .free)
        XCTAssertEqual(CustomerStatus(raw: ""), .free)
        XCTAssertEqual(CustomerStatus(raw: "mystery"), .other("mystery"))
    }

    // MARK: - canManageLists (real subscriber gate — GitHub #40)

    /// The M3 permissive default is gone: `canManageLists` now tracks
    /// `customerStatus` like every other create gate.
    func test_givenDefaultConstruction_whenAskingCanManageLists_thenTracksSubscriberStatus() {
        XCTAssertFalse(EntitlementsService(customerStatus: .free).canManageLists)
        XCTAssertTrue(EntitlementsService(customerStatus: .subscriber).canManageLists)
        XCTAssertFalse(EntitlementsService(user: nil).canManageLists)
    }

    /// `canManageLists` is a create-only gate, so it must agree exactly with
    /// `isEnabled(.listCreation)` — the two must never drift apart.
    func test_givenAnyStatus_whenAskingCanManageLists_thenAgreesWithListCreationFeature() {
        for status: CustomerStatus in [.subscriber, .free, .other("trialing")] {
            let service = EntitlementsService(customerStatus: status)
            XCTAssertEqual(
                service.canManageLists,
                service.isEnabled(.listCreation),
                "canManageLists drifted from .listCreation for \(status)"
            )
        }
    }

    func test_givenOverrideToFalse_whenAskingCanManageLists_thenBlocks() {
        // Given — the explicit test seam, retained so a suite can exercise the
        // blocked path without standing up a whole account.
        let service = EntitlementsService(customerStatus: .subscriber, canManageLists: false)

        // Then
        XCTAssertFalse(service.canManageLists)
        // Other subscriber features remain governed by their own switch.
        XCTAssertTrue(service.isEnabled(.mediaAttachments))
    }

    func test_givenOverrideToTrueOnFreeAccount_whenAskingCanManageLists_thenAllows() {
        // Given — the override stays authoritative over the status-driven default.
        let service = EntitlementsService(customerStatus: .free, canManageLists: true)

        // Then
        XCTAssertTrue(service.canManageLists)
    }

    // MARK: - The documented matrix (GitHub #40)

    /// Every feature named subscriber-only by `/help/settings` must be modelled.
    /// This is the regression guard for "the app models 3, the platform gates ~10".
    func test_givenSubscriber_whenCheckingEveryDocumentedFeature_thenAllAreModelledAndEnabled() {
        let service = EntitlementsService(customerStatus: .subscriber)
        let documented: [Feature] = [
            .mediaAttachments, .scheduledPosts, .crossPosting,
            .listCreation, .listFolderCreation,
            .documentCreation, .documentTemplateCreation,
            .organizationCreation,
            .sharingWithPeople, .emailInvites, .shareLinkCreation,
            .aiFeatures,
        ]
        XCTAssertEqual(
            Set(documented), Set(Feature.allCases),
            "Feature drifted from the documented Free/Subscriber matrix."
        )
        for feature in documented {
            XCTAssertTrue(service.isEnabled(feature), "\(feature) should be enabled for a subscriber")
        }
    }

    /// Every feature must carry distinct, non-empty upgrade copy, so an
    /// upgrade prompt can always name what the user was trying to do.
    func test_givenEveryFeature_whenAskingUpgradeMessage_thenCopyIsPresentAndDistinct() {
        let messages = Feature.allCases.map(\.upgradeMessage)
        XCTAssertFalse(messages.contains { $0.isEmpty })
        XCTAssertEqual(Set(messages).count, Feature.allCases.count, "Upgrade copy must be per-feature")
    }

    // MARK: - Helpers

    private func makeUser(status: CustomerStatus) -> CurrentUser {
        CurrentUser(
            summary: UserSummary(id: "1", username: "ada", displayName: "Ada"),
            email: "ada@example.com",
            customerStatus: status,
            isEmailVerified: true,
            isPrivateAccount: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
