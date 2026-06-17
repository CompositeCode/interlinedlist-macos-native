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
