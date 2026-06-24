import Foundation

/// The deep-link target a notification routes to when activated (PLAN.md §1
/// "Notifications / native UNUserNotification delivery", §5 "Handoff /
/// universal links", §6 M5).
///
/// `NotificationDTO.metadata` is a flexible map whose keys vary by
/// `NotificationKind`. The domain layer projects each shape into a typed
/// target so the App layer's deep-link router does not have to read the raw
/// metadata map. The mapping rules live in `NotificationMappers.swift`.
///
/// **Routing keys.** When the API ships a stable `routePath` (per [API-backend-
/// prompts-to-build.md item 2.4]) this enum can be reduced or replaced by a
/// plain `URL` — until then the typed cases give the router enough to
/// reconstruct a deep link without mining the raw map at every call site.
public enum NotificationTarget: Sendable, Equatable, Hashable {

    /// Open the message with this id (dig, reply, mention).
    case message(id: String)

    /// Open the list with this id (list_shared, list_row_added).
    case list(id: String)

    /// Open the user profile with this id (follow_request, follow_accepted).
    case user(id: String)

    /// Open the organization with this id (org_invite).
    case organization(id: String)

    /// Forward-compat: no typed projection was possible from the metadata
    /// the server sent. The associated value preserves the raw `actionUrl`
    /// when the DTO carries one, so a generic "open in browser" fallback is
    /// possible. `nil` when no URL was provided either.
    case unknown(actionURL: URL?)
}
