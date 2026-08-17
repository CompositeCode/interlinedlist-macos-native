import Foundation
import InterlinedKit

/// The user's server-synced account preferences (work-consolidation.md — settings
/// storage). Read from `GET /api/user` and written with `POST /api/user/update`.
///
/// This is the domain projection of the editable preference fields on `UserDTO`.
/// It intentionally covers only the settings with clear, verified semantics —
/// booleans and a page-size integer. `theme` and `viewingPreference` are carried
/// on the wire too, but their valid value sets aren't confirmed yet, so they are
/// left out of this typed surface (a `POST /api/user/update` omits nil fields, so
/// leaving them out never clobbers them). Adding them is a follow-up once the
/// server documents the allowed values.
public struct UserSettings: Sendable, Equatable {

    /// New posts default to public visibility rather than private.
    public var defaultPubliclyVisible: Bool
    /// Render rich link-preview cards on posts.
    public var showPreviews: Bool
    /// Reveal the advanced post options (scheduling / cross-post / media) by
    /// default in the composer.
    public var showAdvancedPostSettings: Bool
    /// The account is private (followers must be approved).
    public var isPrivateAccount: Bool
    /// How many posts a feed page requests.
    public var messagesPerPage: Int

    public init(
        defaultPubliclyVisible: Bool,
        showPreviews: Bool,
        showAdvancedPostSettings: Bool,
        isPrivateAccount: Bool,
        messagesPerPage: Int
    ) {
        self.defaultPubliclyVisible = defaultPubliclyVisible
        self.showPreviews = showPreviews
        self.showAdvancedPostSettings = showAdvancedPostSettings
        self.isPrivateAccount = isPrivateAccount
        self.messagesPerPage = messagesPerPage
    }

    /// Sensible fallbacks used for any field the server omits, so a partial
    /// payload never yields a nonsensical setting (e.g. a zero page size).
    public static let `default` = UserSettings(
        defaultPubliclyVisible: true,
        showPreviews: true,
        showAdvancedPostSettings: false,
        isPrivateAccount: false,
        messagesPerPage: 20
    )
}

public extension UserSettings {

    /// Maps the editable preference fields off a decoded `UserDTO`, falling back
    /// to `default` for any absent field.
    init(from dto: UserDTO) {
        let fallback = UserSettings.default
        self.init(
            defaultPubliclyVisible: dto.defaultPubliclyVisible ?? fallback.defaultPubliclyVisible,
            showPreviews: dto.showPreviews ?? fallback.showPreviews,
            showAdvancedPostSettings: dto.showAdvancedPostSettings ?? fallback.showAdvancedPostSettings,
            isPrivateAccount: dto.isPrivateAccount ?? fallback.isPrivateAccount,
            messagesPerPage: dto.messagesPerPage ?? fallback.messagesPerPage
        )
    }

    /// The `POST /api/user/update` body that persists this settings snapshot.
    /// All five managed fields are sent so the pane's "Save" applies the full
    /// current state; other profile fields (name, bio, theme, …) are left nil
    /// and therefore untouched.
    var updateRequest: UpdateUserRequest {
        UpdateUserRequest(
            defaultPubliclyVisible: defaultPubliclyVisible,
            messagesPerPage: messagesPerPage,
            showPreviews: showPreviews,
            showAdvancedPostSettings: showAdvancedPostSettings,
            isPrivateAccount: isPrivateAccount
        )
    }
}
