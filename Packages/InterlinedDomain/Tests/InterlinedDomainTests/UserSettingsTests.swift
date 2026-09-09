import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the `UserSettings` mapper + update-request builder
/// (work-consolidation.md — settings storage; G35 / issue #43 for the View
/// Preferences completion: the clamped ranges, `viewingPreference`, and
/// `notificationTrayLimit`).
final class UserSettingsTests: XCTestCase {

    private func dto(
        defaultPubliclyVisible: Bool? = nil,
        messagesPerPage: Int? = nil,
        viewingPreference: String? = nil,
        showPreviews: Bool? = nil,
        showAdvancedPostSettings: Bool? = nil,
        isPrivateAccount: Bool? = nil,
        notificationTrayLimit: Int? = nil
    ) -> UserDTO {
        UserDTO(
            id: "u1",
            email: "ada@example.com",
            username: "ada",
            emailVerified: true,
            defaultPubliclyVisible: defaultPubliclyVisible,
            messagesPerPage: messagesPerPage,
            viewingPreference: viewingPreference,
            showPreviews: showPreviews,
            showAdvancedPostSettings: showAdvancedPostSettings,
            isPrivateAccount: isPrivateAccount,
            customerStatus: "free",
            notificationTrayLimit: notificationTrayLimit,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Happy path

    func test_givenFullDTO_whenMapping_thenReadsEveryPreferenceField() {
        let settings = UserSettings(from: dto(
            defaultPubliclyVisible: false,
            messagesPerPage: 25,
            viewingPreference: "followers_only",
            showPreviews: false,
            showAdvancedPostSettings: true,
            isPrivateAccount: true,
            notificationTrayLimit: 35
        ))

        XCTAssertFalse(settings.defaultPubliclyVisible)
        XCTAssertEqual(settings.messagesPerPage, 25)
        XCTAssertEqual(settings.viewingPreference, .followersOnly)
        XCTAssertFalse(settings.showPreviews)
        XCTAssertTrue(settings.showAdvancedPostSettings)
        XCTAssertTrue(settings.isPrivateAccount)
        XCTAssertEqual(settings.notificationTrayLimit, 35)
    }

    /// Happy path from the issue's test plan: "each of the four viewing
    /// preferences round-trips". Wire token in → typed case → same token out.
    func test_givenEachDocumentedViewingPreference_whenRoundTripped_thenTokenSurvives() {
        let expectations: [(token: String, expected: ViewingPreference)] = [
            ("my_messages", .myMessages),
            ("all_messages", .allMessages),
            ("followers_only", .followersOnly),
            ("following_only", .followingOnly)
        ]

        for expectation in expectations {
            let settings = UserSettings(from: dto(viewingPreference: expectation.token))
            XCTAssertEqual(
                settings.viewingPreference,
                expectation.expected,
                "\(expectation.token) did not decode to the expected case"
            )
            XCTAssertEqual(
                settings.updateRequest.viewingPreference,
                expectation.token,
                "\(expectation.token) did not round-trip back onto the wire"
            )
        }
    }

    // MARK: - Invalid input

    /// An unrecognised token must not throw and must not be rewritten: it is
    /// carried verbatim for round-trip, and only the *scope* falls back to All.
    func test_givenUnrecognisedViewingPreference_whenMapping_thenFallsBackToAllWithoutLosingTheToken() {
        let settings = UserSettings(from: dto(viewingPreference: "quantum_only"))

        XCTAssertEqual(settings.viewingPreference, .other("quantum_only"))
        XCTAssertEqual(settings.viewingPreference.defaultScope, .all)
        XCTAssertEqual(
            settings.updateRequest.viewingPreference,
            "quantum_only",
            "A save must not clobber a preference this build doesn't understand"
        )
    }

    func test_givenMissingFields_whenMapping_thenFallsBackToDefaults() {
        let settings = UserSettings(from: dto())   // all preference fields nil
        XCTAssertEqual(settings, .default)
        XCTAssertEqual(settings.viewingPreference, .allMessages)
        XCTAssertEqual(settings.notificationTrayLimit, 20)
    }

    // MARK: - Boundary (the issue's 9/10/30/31 and 9/10/40/41 cases)

    func test_givenOutOfRangeMessagesPerPage_whenMapping_thenClampsToTheWebsRange() {
        // Below, at, at, above — the two interior values must pass through.
        XCTAssertEqual(UserSettings(from: dto(messagesPerPage: 9)).messagesPerPage, 10)
        XCTAssertEqual(UserSettings(from: dto(messagesPerPage: 10)).messagesPerPage, 10)
        XCTAssertEqual(UserSettings(from: dto(messagesPerPage: 30)).messagesPerPage, 30)
        XCTAssertEqual(UserSettings(from: dto(messagesPerPage: 31)).messagesPerPage, 30)
        // The legacy value the old `5...100 step 5` control could save.
        XCTAssertEqual(UserSettings(from: dto(messagesPerPage: 5)).messagesPerPage, 10)
        XCTAssertEqual(UserSettings(from: dto(messagesPerPage: 100)).messagesPerPage, 30)
    }

    func test_givenOutOfRangeNotificationTrayLimit_whenMapping_thenClampsToTheWebsRange() {
        XCTAssertEqual(UserSettings(from: dto(notificationTrayLimit: 9)).notificationTrayLimit, 10)
        XCTAssertEqual(UserSettings(from: dto(notificationTrayLimit: 10)).notificationTrayLimit, 10)
        XCTAssertEqual(UserSettings(from: dto(notificationTrayLimit: 40)).notificationTrayLimit, 40)
        XCTAssertEqual(UserSettings(from: dto(notificationTrayLimit: 41)).notificationTrayLimit, 40)
    }

    /// Clamping has to hold on *write* too, not just on read — a view model
    /// assigning straight into the working copy must not be able to produce a
    /// body the web would reject.
    func test_givenOutOfRangeAssignment_whenBuildingUpdateRequest_thenSendsClampedValues() {
        var settings = UserSettings.default

        settings.messagesPerPage = 100
        settings.notificationTrayLimit = 1

        XCTAssertEqual(settings.messagesPerPage, 30)
        XCTAssertEqual(settings.notificationTrayLimit, 10)
        XCTAssertEqual(settings.updateRequest.messagesPerPage, 30)
        XCTAssertEqual(settings.updateRequest.notificationTrayLimit, 10)
    }

    // MARK: - Update request

    func test_givenSettings_whenBuildingUpdateRequest_thenSendsManagedFieldsOnly() {
        let settings = UserSettings(
            defaultPubliclyVisible: false,
            showPreviews: true,
            showAdvancedPostSettings: true,
            isPrivateAccount: false,
            messagesPerPage: 25,
            viewingPreference: .myMessages,
            notificationTrayLimit: 30
        )

        let request = settings.updateRequest

        XCTAssertEqual(request.defaultPubliclyVisible, false)
        XCTAssertEqual(request.showPreviews, true)
        XCTAssertEqual(request.showAdvancedPostSettings, true)
        XCTAssertEqual(request.isPrivateAccount, false)
        XCTAssertEqual(request.messagesPerPage, 25)
        XCTAssertEqual(request.viewingPreference, "my_messages")
        XCTAssertEqual(request.notificationTrayLimit, 30)
        // Profile-only fields stay nil so a settings save never clobbers them.
        XCTAssertNil(request.displayName)
        XCTAssertNil(request.bio)
        XCTAssertNil(request.theme)
    }
}
