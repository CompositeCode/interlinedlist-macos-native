// OrgRolePresentation
//
// App-layer presentation helpers for the domain `OrgRole`. Kept in the
// feature folder (not the domain package) because display strings are a
// UI concern, not a domain one. Renders `.other(String)` gracefully by
// surfacing the raw token so an unexpected server role is still legible
// rather than hidden (PLAN.md §6 M6 — "render OrgRole.other gracefully").
//
// Per decision 0003 this consumes only `InterlinedDomain`.

import Foundation
import InterlinedDomain

extension OrgRole {

    /// Human-readable label for the role. Unknown tokens (`.other`) show the
    /// raw string capitalized so the roster never renders an empty cell.
    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .member: return "Member"
        case .other(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Unknown" : trimmed.capitalized
        }
    }

    /// The roles the role editor offers as promote / demote targets. Only the
    /// three documented roles are assignable; an `.other` role is preserved
    /// for display but never offered as a target (the client doesn't invent
    /// taxonomy).
    static var assignableRoles: [OrgRole] {
        [.owner, .admin, .member]
    }
}
