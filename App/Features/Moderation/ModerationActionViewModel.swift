// ModerationActionViewModel
//
// Backs the reusable `ModerationMenu` + `ReportReasonSheet` (work-consolidation.md
// G2). One instance drives the moderation affordances for a single
// subject — a user (by username) and optionally a specific message (by
// id). Reads through `ModerationServicing` only so unit tests substitute
// a stub.
//
// Responsibilities:
//   - block / mute a user (fire-and-forget; success flips `isBlocked` /
//     `isMuted` so the menu can reflect the new state).
//   - submit a user or message report with a `ReportReason` + optional
//     free-text detail. `reportMessage` requires a message id; calling it
//     without one is rejected before the service is touched.
//   - surface a single `error` for the view to present.
//
// The report action validates its subject before any service call: a
// message report with no `messageID` never reaches the network. This is
// the "invalid input rejected before the service is called" gate the
// test quartet asserts on.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ModerationActionViewModel {

    // MARK: - Subject

    /// The username the moderation actions target. Block / mute / report-
    /// user all key off this.
    let username: String

    /// The message id when the subject is a specific message (timeline
    /// row overflow menu). `nil` when the subject is a profile — in which
    /// case `reportMessage` is unavailable and rejected.
    let messageID: String?

    // MARK: - Dependencies

    private let service: ModerationServicing

    // MARK: - Observable state

    /// Reflects the last known block state so the menu can show
    /// "Unblock" instead of "Block". Optimistically updated on a
    /// successful `block()` / `unblock()`.
    private(set) var isBlocked: Bool = false

    /// Reflects the last known mute state, updated the same way.
    private(set) var isMuted: Bool = false

    /// True while any action round-trip is in flight.
    private(set) var isBusy: Bool = false

    /// Surfaced error from the most recent failed action. Cleared at the
    /// start of the next action.
    private(set) var error: Error?

    /// Set true after a report submits successfully so the view can show
    /// a confirmation and dismiss the sheet. Reset when a new report
    /// begins.
    private(set) var didSubmitReport: Bool = false

    // MARK: - Init

    init(username: String, messageID: String? = nil, service: ModerationServicing) {
        self.username = username
        self.messageID = messageID
        self.service = service
    }

    /// Whether a message report is available for this subject. `false`
    /// for a profile subject (no message id).
    var canReportMessage: Bool { messageID != nil }

    // MARK: - Intents

    func block() async {
        await run { [self] in
            try await service.block(username: username)
            isBlocked = true
        }
    }

    func unblock() async {
        await run { [self] in
            try await service.unblock(username: username)
            isBlocked = false
        }
    }

    func mute() async {
        await run { [self] in
            try await service.mute(username: username)
            isMuted = true
        }
    }

    func unmute() async {
        await run { [self] in
            try await service.unmute(username: username)
            isMuted = false
        }
    }

    /// Reports the subject user with a reason + optional detail.
    func reportUser(reason: ReportReason, detail: String?) async {
        didSubmitReport = false
        await run { [self] in
            try await service.reportUser(username: username, reason: reason, detail: detail)
            didSubmitReport = true
        }
    }

    /// Reports the subject message. Rejected before any service call when
    /// there is no `messageID` — a profile subject cannot report a
    /// message. The rejection surfaces `ModerationActionError.noMessageSubject`
    /// and leaves the service untouched.
    func reportMessage(reason: ReportReason, detail: String?) async {
        didSubmitReport = false
        guard let messageID else {
            error = ModerationActionError.noMessageSubject
            return
        }
        await run { [self] in
            try await service.reportMessage(id: messageID, reason: reason, detail: detail)
            didSubmitReport = true
        }
    }

    // MARK: - Internals

    /// Runs one action with uniform busy / error bookkeeping.
    private func run(_ body: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await body()
        } catch {
            self.error = error
        }
    }
}

// MARK: - ModerationActionError

/// Local validation errors raised before any service call.
enum ModerationActionError: Error, Equatable {
    /// `reportMessage` was invoked on a subject that has no message id.
    case noMessageSubject
}
