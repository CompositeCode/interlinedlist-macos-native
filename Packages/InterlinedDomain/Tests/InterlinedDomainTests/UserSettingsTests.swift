import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the `UserSettings` mapper + update-request builder
/// (work-consolidation.md — settings storage).
final class UserSettingsTests: XCTestCase {

    private func dto(
        defaultPubliclyVisible: Bool? = nil,
        messagesPerPage: Int? = nil,
        showPreviews: Bool? = nil,
        showAdvancedPostSettings: Bool? = nil,
        isPrivateAccount: Bool? = nil
    ) -> UserDTO {
        UserDTO(
            id: "u1",
            email: "ada@example.com",
            username: "ada",
            emailVerified: true,
            defaultPubliclyVisible: defaultPubliclyVisible,
            messagesPerPage: messagesPerPage,
            showPreviews: showPreviews,
            showAdvancedPostSettings: showAdvancedPostSettings,
            isPrivateAccount: isPrivateAccount,
            customerStatus: "free",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func test_givenFullDTO_whenMapping_thenReadsEveryPreferenceField() {
        let settings = UserSettings(from: dto(
            defaultPubliclyVisible: false,
            messagesPerPage: 42,
            showPreviews: false,
            showAdvancedPostSettings: true,
            isPrivateAccount: true
        ))

        XCTAssertFalse(settings.defaultPubliclyVisible)
        XCTAssertEqual(settings.messagesPerPage, 42)
        XCTAssertFalse(settings.showPreviews)
        XCTAssertTrue(settings.showAdvancedPostSettings)
        XCTAssertTrue(settings.isPrivateAccount)
    }

    func test_givenMissingFields_whenMapping_thenFallsBackToDefaults() {
        let settings = UserSettings(from: dto())   // all preference fields nil
        XCTAssertEqual(settings, .default)
    }

    func test_givenSettings_whenBuildingUpdateRequest_thenSendsManagedFieldsOnly() {
        let settings = UserSettings(
            defaultPubliclyVisible: false,
            showPreviews: true,
            showAdvancedPostSettings: true,
            isPrivateAccount: false,
            messagesPerPage: 25
        )

        let request = settings.updateRequest

        XCTAssertEqual(request.defaultPubliclyVisible, false)
        XCTAssertEqual(request.showPreviews, true)
        XCTAssertEqual(request.showAdvancedPostSettings, true)
        XCTAssertEqual(request.isPrivateAccount, false)
        XCTAssertEqual(request.messagesPerPage, 25)
        // Profile-only fields stay nil so a settings save never clobbers them.
        XCTAssertNil(request.displayName)
        XCTAssertNil(request.bio)
        XCTAssertNil(request.theme)
        XCTAssertNil(request.viewingPreference)
    }
}
