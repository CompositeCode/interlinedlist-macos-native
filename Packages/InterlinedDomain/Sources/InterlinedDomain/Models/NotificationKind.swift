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

    /// Someone pushed (reposted) one of the caller's messages.
    ///
    /// The server distinguishes a plain push from one with commentary
    /// (`message_push_plain` vs `message_push_commentary`) and carries the
    /// comment text in `metadata.commentary`. One case with a flag rather than
    /// two, because every consumer wants "was this reposted" first and "with a
    /// comment" second.
    case push(hasCommentary: Bool)

    /// A cross-posting connection needs reconnecting before it quietly stops
    /// working. The only notification type on this account that is not about
    /// another person.
    case integrationReconnect

    /// Someone sent the caller a direct message.
    ///
    /// The server lists `direct_message` in its notification-preferences
    /// catalogue, so it does emit these — but no DM notification has been
    /// observed on the recon account, so **the exact `type` token is
    /// unconfirmed**. Both the bare and the `message_`-prefixed spellings are
    /// accepted for that reason. This is the producer the DM deep-link seam has
    /// been waiting for (GitHub #77); wiring it is a follow-up once a real row
    /// confirms the token.
    case directMessage

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
        // Both spellings are accepted on purpose.
        //
        // The client matched only the **bare** tokens (`"dig"`, `"mention"`)
        // while the server sends **prefixed** ones (`"message_dig"`,
        // `"message_mention"`) — so every one of the 37 notifications on the
        // recon account fell to `.other`, every row rendered as a generic bell,
        // and the deep-link router's per-kind branches never fired (GitHub #95).
        //
        // Matching only the newly-observed spelling would repeat the same
        // mistake in the other direction. This defect is itself the evidence
        // that the vocabulary is not fixed, and accepting both costs nothing.
        switch rawValue {
        case "dig", "message_dig":
            self = .dig
        case "reply", "message_reply":
            self = .reply
        case "mention", "message_mention":
            self = .mention
        case "push", "message_push", "message_push_plain":
            self = .push(hasCommentary: false)
        case "message_push_commentary":
            self = .push(hasCommentary: true)
        case "integration_reconnect":
            self = .integrationReconnect
        case "direct_message", "message_direct", "dm":
            self = .directMessage
        case "follow_request":   self = .followRequest
        case "follow_accepted":  self = .followAccepted
        case "list_shared":      self = .listShared
        case "list_row_added":   self = .listRowAdded
        case "org_invite":       self = .orgInvite
        default:                 self = .other(rawValue)
        }
    }

    /// Whether this kind points at a message.
    ///
    /// The deep-link router used to read the target id under an allowlist of
    /// three cases, which meant a new message-shaped kind silently stopped
    /// resolving. Asking the kind is the version that keeps working.
    public var isMessageShaped: Bool {
        switch self {
        case .dig, .reply, .mention, .push:
            return true
        case .followRequest, .followAccepted, .listShared, .listRowAdded,
             .orgInvite, .integrationReconnect, .directMessage, .other:
            return false
        }
    }

    /// The wire string this case maps to. Useful for round-trip tests and
    /// for any client-to-server echo (none today, but the protocol is
    /// symmetric so the property is cheap to maintain).
    public var rawValue: String {
        switch self {
        // The **server's** spelling, so a round-trip produces what the wire
        // would have sent rather than the token this client used to expect.
        case .dig:               return "message_dig"
        case .reply:             return "message_reply"
        case .mention:           return "message_mention"
        case .push(let hasCommentary):
            return hasCommentary ? "message_push_commentary" : "message_push_plain"
        case .integrationReconnect: return "integration_reconnect"
        case .directMessage:     return "direct_message"
        case .followRequest:     return "follow_request"
        case .followAccepted:    return "follow_accepted"
        case .listShared:        return "list_shared"
        case .listRowAdded:      return "list_row_added"
        case .orgInvite:         return "org_invite"
        case .other(let raw):    return raw
        }
    }
}
