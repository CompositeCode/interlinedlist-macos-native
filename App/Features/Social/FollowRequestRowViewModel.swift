// FollowRequestRowViewModel
//
// Drives one row of the M5 follow-requests inbox (PLAN.md §1 "Follow
// system / request approval for private accounts", §6 M5). The same
// view model powers the inline Approve / Reject affordance on the
// notifications tray's `followRequest` rows and the dedicated
// "Requests" tab in `SocialRosterRootView`.
//
// Optimistic UI per the swift-engineer skill: each action dispatches
// to `SocialServicing.approve / reject`, posts to the
// `NotificationsEventBus` on success so peer views (the other surface
// rendering the same request) drop the row, and surfaces an error
// without changing the row's "decided" state on failure — the caller
// is expected to re-show the row in that case.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class FollowRequestRowViewModel {

    enum Outcome: Sendable, Equatable {
        /// No action has resolved yet — the row is interactive.
        case undecided
        /// The user approved the request.
        case approved
        /// The user rejected the request.
        case rejected
    }

    // MARK: - Dependencies

    private let social: SocialServicing
    private let bus: NotificationsEventBus?

    // MARK: - Inputs

    let request: FollowRequest

    // MARK: - Observable state

    private(set) var outcome: Outcome = .undecided
    private(set) var isMutating: Bool = false
    private(set) var error: Error?

    // MARK: - Init

    init(
        request: FollowRequest,
        social: SocialServicing,
        notificationsEventBus: NotificationsEventBus? = nil
    ) {
        self.request = request
        self.social = social
        self.bus = notificationsEventBus
    }

    // MARK: - Intents

    /// Approves the request. On success the outcome flips to
    /// `.approved` and a `requestApproved` event is posted on the bus
    /// so other open surfaces (the other panel, the tray inline row)
    /// drop the row. On failure the outcome stays `.undecided` so the
    /// view re-enables the buttons and the error surfaces.
    func approve() async {
        await mutate(to: .approved) { [request, social] in
            try await social.approve(userId: request.user.id)
        }
    }

    /// Rejects the request — symmetric with `approve`.
    func reject() async {
        await mutate(to: .rejected) { [request, social] in
            try await social.reject(userId: request.user.id)
        }
    }

    /// Clears the surfaced error. Bound to a tap-to-dismiss affordance.
    func clearError() {
        error = nil
    }

    // MARK: - Internals

    private func mutate(
        to next: Outcome,
        perform: @Sendable () async throws -> Void
    ) async {
        guard outcome == .undecided, !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await perform()
            outcome = next
            error = nil
            switch next {
            case .approved:
                bus?.post(.requestApproved(requestUserID: request.user.id))
            case .rejected:
                bus?.post(.requestRejected(requestUserID: request.user.id))
            case .undecided:
                break
            }
        } catch {
            self.error = error
            // Outcome stays `.undecided` so the buttons are tappable.
        }
    }
}
