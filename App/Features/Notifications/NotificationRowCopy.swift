// NotificationRowCopy
//
// Pure presentation derivation for one notification row (PLAN.md §1
// "Notifications", §6 M5). Translates a `(NotificationKind, actor)`
// pair into the inline copy string and the SF Symbol shown in the
// tray and the native banner. Pulled into its own file so unit tests
// pin each kind's copy without booting SwiftUI.
//
// The strings here are the v1 wire-level placeholders the brief
// specifies. They're deliberately terse — a Markdown-rendered title
// from the server (the kit's `NotificationDTO.title`) takes
// precedence when present; this file is the fallback path.
//
// Per decision 0003, this file consumes only `InterlinedDomain`.

import Foundation
import InterlinedDomain

/// Pure presenter for one tray row.
enum NotificationRowCopy {

    /// SF Symbol name for the row's leading icon.
    static func symbol(for kind: NotificationKind) -> String {
        switch kind {
        case .dig:             return "hand.thumbsup.fill"
        case .reply:           return "bubble.left.fill"
        case .mention:         return "at"
        case .followRequest:   return "person.crop.circle.badge.questionmark"
        case .followAccepted:  return "person.crop.circle.badge.checkmark"
        case .listShared:      return "list.bullet.rectangle"
        case .listRowAdded:    return "plus.rectangle.on.rectangle"
        case .orgInvite:       return "building.2.crop.circle"
        case .other:           return "bell"
        }
    }

    /// Primary copy for the row. Uses `actor.username` when present,
    /// falling back to the literal "Someone" for system-originated
    /// rows (e.g. a GitHub refresh-job-driven `list_row_added`).
    static func copy(
        for kind: NotificationKind,
        actor: UserSummary?,
        title: String?,
        body: String?
    ) -> String {
        if let title, !title.isEmpty {
            return title
        }
        let handle: String = {
            if let actor, !actor.username.isEmpty {
                return "@" + actor.username
            }
            return "Someone"
        }()
        switch kind {
        case .dig:
            return "\(handle) dug your post"
        case .reply:
            return "\(handle) replied to your post"
        case .mention:
            return "\(handle) mentioned you"
        case .followRequest:
            return "\(handle) wants to follow you"
        case .followAccepted:
            return "\(handle) accepted your follow request"
        case .listShared:
            return "\(handle) shared a list with you"
        case .listRowAdded:
            return "\(handle) added a row to a list"
        case .orgInvite:
            return "\(handle) invited you to an organization"
        case .other(let raw):
            if let body, !body.isEmpty {
                return body
            }
            return "\(handle): \(raw)"
        }
    }
}
