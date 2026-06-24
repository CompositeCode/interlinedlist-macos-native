import Foundation

/// The typed kind enum for a `Notification` (PLAN.md §1 "Notifications",
/// §6 M5).
///
/// The wire format encodes the kind as a free-form string `NotificationDTO.type`
/// (the closed list of values is **not** documented today — the macOS client
/// asked for it on [API-backend-prompts-to-build.md item 2.4]). Until that
/// lands the domain layer maps the value the kit DTO carries to a typed case
/// for every kind we recognize, and falls back to `.other(String)` for
/// forward compatibility. The strings here come from the proposal in
/// item 2.4 (`dig | reply | mention | follow_request | follow_accepted |
/// list_shared | list_row_added | org_invite`) — that proposal is the most
/// authoritative source we have, and it matches the kinds the live API has
/// been observed to emit (`dig`, `reply`) in the kit's contract tests.
///
/// **Why `.other(String)`.** Whenever the server emits a new kind, the
/// existing client should still render the notification rather than fail to
/// decode the entire tray. The `.other` case preserves the raw string so a
/// future client release can pattern-match on it; today it routes to a
/// generic copy. This matches the `WatcherRole.other(String)` pattern from
/// Wave 4 and the same defensive shape M5 social UIs lean on.
public enum NotificationKind: Sendable, Equatable, Hashable {

    /// Someone reacted ("I Dig!") to one of the caller's messages.
    case dig

    /// Someone replied to one of the caller's messages.
    case reply

    /// Someone @mentioned the caller in a message.
    case mention

    /// Someone requested to follow a private account.
    case followRequest

    /// A previously-pending follow request was approved.
    case followAccepted

    /// A list was shared with the caller (watcher invitation).
    case listShared

    /// A row was added to a list the caller watches.
    case listRowAdded

    /// The caller was invited to an organization.
    case orgInvite

    /// Forward-compat: a kind the client does not have a typed case for yet.
    /// The associated value is the raw `type` string from the wire — kept
    /// `Sendable` and `Hashable` so the case threads through SwiftUI
    /// `ForEach` and `Picker` identities without ceremony.
    case other(String)

    /// Maps a raw `NotificationDTO.type` string to a typed case. `nil`
    /// inputs surface as `.other("")` so callers always have a kind to
    /// switch on (the wire-shape allows `type` to be missing; the M5 tray
    /// renders such rows as a generic notification).
    public init(rawValue: String?) {
        guard let rawValue, !rawValue.isEmpty else {
            self = .other("")
            return
        }
        switch rawValue {
        case "dig":              self = .dig
        case "reply":            self = .reply
        case "mention":          self = .mention
        case "follow_request":   self = .followRequest
        case "follow_accepted":  self = .followAccepted
        case "list_shared":      self = .listShared
        case "list_row_added":   self = .listRowAdded
        case "org_invite":       self = .orgInvite
        default:                 self = .other(rawValue)
        }
    }

    /// The wire string this case maps to. Useful for round-trip tests and
    /// for any client-to-server echo (none today, but the protocol is
    /// symmetric so the property is cheap to maintain).
    public var rawValue: String {
        switch self {
        case .dig:               return "dig"
        case .reply:             return "reply"
        case .mention:           return "mention"
        case .followRequest:     return "follow_request"
        case .followAccepted:    return "follow_accepted"
        case .listShared:        return "list_shared"
        case .listRowAdded:      return "list_row_added"
        case .orgInvite:         return "org_invite"
        case .other(let raw):    return raw
        }
    }
}
