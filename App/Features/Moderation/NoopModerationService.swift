// NoopModerationService
//
// Defensive `ModerationServicing` fallback used only when a view needs to
// construct a `ModerationActionViewModel` but the `AppEnvironment` is not
// injected (a programmer error, not a runtime one). Every call is a
// no-op so the UI degrades to inert affordances rather than crashing.
//
// Production surfaces always pass `environment.moderation`; this exists
// so a view can avoid force-unwrapping an optional environment.
//
// Per decision 0003, this file consumes only `InterlinedDomain`.

import Foundation
import InterlinedDomain

struct NoopModerationService: ModerationServicing {
    func blockedUsers(limit: Int, offset: Int) async throws -> [ModeratedUser] { [] }
    func mutedUsers(limit: Int, offset: Int) async throws -> [ModeratedUser] { [] }
    func block(username: String) async throws {}
    func unblock(username: String) async throws {}
    func mute(username: String) async throws {}
    func unmute(username: String) async throws {}
    func reportUser(username: String, reason: ReportReason, detail: String?) async throws {}
    func reportMessage(id: String, reason: ReportReason, detail: String?) async throws {}
    func isBlocking(username: String) async throws -> Bool { false }
}
