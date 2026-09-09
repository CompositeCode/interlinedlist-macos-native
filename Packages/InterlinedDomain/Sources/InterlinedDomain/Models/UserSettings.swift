import Foundation
import InterlinedKit

/// The user's server-synced account preferences (work-consolidation.md — settings
/// storage; G35 / issue #43 for the View Preferences completion). Read from
/// `GET /api/user` and written with `PATCH /api/user/update`.
///
/// This is the domain projection of the editable preference fields on `UserDTO`.
/// `theme` is still carried on the wire only — its valid value set is unverified,
/// and an update omits nil fields, so leaving it out never clobbers it.
///
/// **Ranges are enforced here, not just in the UI.** The web's View Preferences
/// card validates `messagesPerPage` to 10...30 and `notificationTrayLimit` to
/// 10...40 before it will PATCH (verified against the live client 2026-09-09), so
/// a value outside those bounds is unrepresentable on the web. Both fields are
/// therefore clamped on *read* as well as on *write*: an account that already
/// stores an out-of-range value (the macOS pane used to offer `5...100`) is
/// corrected on load rather than re-sending the bad value.
public struct UserSettings: Sendable, Equatable {

    /// Values the web's "Messages per page" control accepts (`min=10 max=30`).
    public static let messagesPerPageRange: ClosedRange<Int> = 10...30

    /// Values the web's "Notifications in tray" control accepts
    /// (`min=10 max=40`, default 20).
    public static let notificationTrayLimitRange: ClosedRange<Int> = 10...40

    /// New posts default to public visibility rather than private.
    public var defaultPubliclyVisible: Bool
    /// Render rich link-preview cards on posts.
    public var showPreviews: Bool
    /// Reveal the advanced post options (media / scheduling / cross-post) by
    /// default in the composer — the "gear" affordance the web describes.
    public var showAdvancedPostSettings: Bool
    /// The account is private (followers must be approved).
    public var isPrivateAccount: Bool
    /// Which slice of the feed the account wants by default.
    public var viewingPreference: ViewingPreference

    /// How many posts a feed page requests. Always within
    /// `messagesPerPageRange` — the setter clamps.
    public var messagesPerPage: Int {
        get { storedMessagesPerPage }
        set { storedMessagesPerPage = Self.clamp(newValue, to: Self.messagesPerPageRange) }
    }

    /// How many rows the notification bell tray holds. Always within
    /// `notificationTrayLimitRange` — the setter clamps.
    public var notificationTrayLimit: Int {
        get { storedNotificationTrayLimit }
        set { storedNotificationTrayLimit = Self.clamp(newValue, to: Self.notificationTrayLimitRange) }
    }

    /// Backing storage for the two clamped properties. Private so no caller can
    /// route around the clamp; `Equatable` still compares them because synthesised
    /// conformance uses stored properties.
    private var storedMessagesPerPage: Int
    private var storedNotificationTrayLimit: Int

    public init(
        defaultPubliclyVisible: Bool,
        showPreviews: Bool,
        showAdvancedPostSettings: Bool,
        isPrivateAccount: Bool,
        messagesPerPage: Int,
        viewingPreference: ViewingPreference = .allMessages,
        notificationTrayLimit: Int = 20
    ) {
        self.defaultPubliclyVisible = defaultPubliclyVisible
        self.showPreviews = showPreviews
        self.showAdvancedPostSettings = showAdvancedPostSettings
        self.isPrivateAccount = isPrivateAccount
        self.viewingPreference = viewingPreference
        self.storedMessagesPerPage = Self.clamp(messagesPerPage, to: Self.messagesPerPageRange)
        self.storedNotificationTrayLimit = Self.clamp(
            notificationTrayLimit,
            to: Self.notificationTrayLimitRange
        )
    }

    /// Sensible fallbacks used for any field the server omits, so a partial
    /// payload never yields a nonsensical setting (e.g. a zero page size).
    /// Matches the server's own defaults: `all_messages`, tray limit 20.
    public static let `default` = UserSettings(
        defaultPubliclyVisible: true,
        showPreviews: true,
        showAdvancedPostSettings: false,
        isPrivateAccount: false,
        messagesPerPage: 20,
        viewingPreference: .allMessages,
        notificationTrayLimit: 20
    )

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public extension UserSettings {

    /// Maps the editable preference fields off a decoded `UserDTO`, falling back
    /// to `default` for any absent field. Out-of-range integers are clamped by
    /// the initializer, so a legacy stored value (e.g. `messagesPerPage: 5`
    /// saved by an older macOS build) is corrected on load.
    init(from dto: UserDTO) {
        let fallback = UserSettings.default
        self.init(
            defaultPubliclyVisible: dto.defaultPubliclyVisible ?? fallback.defaultPubliclyVisible,
            showPreviews: dto.showPreviews ?? fallback.showPreviews,
            showAdvancedPostSettings: dto.showAdvancedPostSettings ?? fallback.showAdvancedPostSettings,
            isPrivateAccount: dto.isPrivateAccount ?? fallback.isPrivateAccount,
            messagesPerPage: dto.messagesPerPage ?? fallback.messagesPerPage,
            viewingPreference: dto.viewingPreference.map(ViewingPreference.init(wireToken:))
                ?? fallback.viewingPreference,
            notificationTrayLimit: dto.notificationTrayLimit ?? fallback.notificationTrayLimit
        )
    }

    /// The `PATCH /api/user/update` body that persists this settings snapshot.
    /// All seven managed fields are sent so the pane's "Save" applies the full
    /// current state; other profile fields (name, bio, theme, …) are left nil
    /// and therefore untouched.
    ///
    /// The two integers are read through the clamped accessors, so this body can
    /// never carry a value the web would reject.
    var updateRequest: UpdateUserRequest {
        UpdateUserRequest(
            defaultPubliclyVisible: defaultPubliclyVisible,
            messagesPerPage: messagesPerPage,
            viewingPreference: viewingPreference.wireToken,
            showPreviews: showPreviews,
            showAdvancedPostSettings: showAdvancedPostSettings,
            isPrivateAccount: isPrivateAccount,
            notificationTrayLimit: notificationTrayLimit
        )
    }
}
