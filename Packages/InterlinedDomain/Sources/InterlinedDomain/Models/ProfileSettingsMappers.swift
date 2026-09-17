import Foundation
import InterlinedKit

// MARK: - ProfileSettings ⇄ wire

public extension ProfileSettings {

    /// Projects the account payload.
    ///
    /// Note what is **not** defaulted: `theme` passes through `AppTheme.init(wireToken:)`,
    /// which preserves an unrecognised value rather than collapsing it to
    /// `.system`. The server does not validate this field at all (probed live
    /// 2026-09-15 — it stored `"nonsense"` happily), so a value this client does
    /// not know is a real possibility and must survive a round-trip.
    init(from dto: UserDTO) {
        self.init(
            displayName: dto.displayName ?? "",
            bio: dto.bio ?? "",
            theme: dto.theme.map(AppTheme.init(wireToken:)) ?? .system,
            maxMessageLength: dto.maxMessageLength ?? 666,
            avatarURL: dto.avatar.flatMap(URL.init(string:)),
            location: ProfileLocation(latitude: dto.latitude, longitude: dto.longitude)
        )
    }

    /// The PATCH body for a save, carrying **only what changed**.
    ///
    /// `UpdateUserRequest` omits nil fields, so a change-gated body is how an
    /// untouched field stays untouched. Sending the whole object every time
    /// would make every save a full overwrite, and two windows open on the same
    /// account would clobber each other's edits.
    func updateRequest(changedFrom original: ProfileSettings) -> UpdateUserRequest {
        UpdateUserRequest(
            displayName: displayName == original.displayName ? nil : displayName,
            bio: bio == original.bio ? nil : bio,
            theme: theme == original.theme ? nil : theme.wireToken,
            maxMessageLength: maxMessageLength == original.maxMessageLength ? nil : maxMessageLength
        )
    }

    /// `true` when nothing differs — the Save button's enablement, and the guard
    /// that stops a no-op PATCH going out at all.
    func hasChanges(from original: ProfileSettings) -> Bool {
        displayName != original.displayName
            || bio != original.bio
            || theme != original.theme
            || maxMessageLength != original.maxMessageLength
    }

    /// Client-side validation, run before the call.
    ///
    /// Only rules with real backing:
    ///
    /// - `maxMessageLength` is clamped by the setter, so it cannot be invalid
    ///   here; the server's `1...10000` is mirrored in
    ///   `maxMessageLengthRange`.
    /// - An **empty display name is valid** — the server falls back to the
    ///   username, which is exactly what `/help/settings` documents, so
    ///   rejecting it would invent a rule.
    /// - The bio bound is a **client-side sanity limit**; the server states
    ///   none. Flagged as such so it is never mistaken for a verified rule.
    var validationError: ProfileSettingsError? {
        if bio.count > Self.bioLengthLimit {
            return .bioTooLong(limit: Self.bioLengthLimit)
        }
        return nil
    }
}

/// Failures the profile pane can report without a round-trip.
public enum ProfileSettingsError: Error, Sendable, Equatable {
    case bioTooLong(limit: Int)
}

extension ProfileSettingsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bioTooLong(let limit):
            return "Your bio is longer than \(limit) characters."
        }
    }
}
