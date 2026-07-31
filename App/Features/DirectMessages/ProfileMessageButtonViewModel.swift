// ProfileMessageButtonViewModel
//
// Backs the additive "Message" affordance on `ProfileHeaderView` (the-
// gaps.md G1). The button opens a DM thread with the profiled user, but
// only when that user is an *eligible recipient* — a mutual follower who
// has not blocked the current user. Eligibility is server-defined: the
// authoritative source is `recipients()` (the mutual-follower set), so we
// check membership by username rather than re-deriving mutual state on the
// client.
//
// Ownership-gating (per the swift-engineer skill): while the current user
// is unknown (session not resolved) OR the profiled user is the current
// user OR the eligibility check has not yet resolved, the button hides
// itself. `isEligible == nil` is the "hidden / undetermined" signal; only
// `true` renders the button. This never renders an enabled-but-broken
// action.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ProfileMessageButtonViewModel {

    // MARK: - Subject

    /// The profiled user's username.
    let username: String

    // MARK: - Dependencies

    private let service: DirectMessagesServicing
    private let currentUsernameProvider: @MainActor () -> String?

    // MARK: - Observable state

    /// Tri-state eligibility:
    ///   - `nil`   — undetermined (not yet checked) OR gated (self /
    ///               unknown session); the button hides.
    ///   - `false` — checked, not a mutual recipient; the button hides.
    ///   - `true`  — checked, eligible; the button shows.
    private(set) var isEligible: Bool?

    /// True while the eligibility check is in flight.
    private(set) var isChecking: Bool = false

    /// Whether the button should render. Only a resolved `true` shows it.
    var shouldShow: Bool { isEligible == true }

    // MARK: - Init

    init(
        username: String,
        service: DirectMessagesServicing,
        currentUsername: @MainActor @escaping () -> String? = { nil }
    ) {
        self.username = username
        self.service = service
        self.currentUsernameProvider = currentUsername
    }

    // MARK: - Intents

    /// Resolves eligibility. Short-circuits to hidden (`nil`) when the
    /// session is unresolved or the subject is the current user — neither
    /// case should touch the network. Otherwise checks membership of the
    /// `recipients()` set. A failed check leaves the button hidden
    /// (`isEligible == false`) rather than surfacing an error — a
    /// best-effort affordance should fail closed.
    func check() async {
        guard let me = currentUsernameProvider() else {
            // Unresolved session — hide, don't check.
            isEligible = nil
            return
        }
        guard me != username else {
            // Self-profile — no "Message yourself".
            isEligible = false
            return
        }
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let recipients = try await service.recipients()
            isEligible = recipients.contains { $0.username == username }
        } catch {
            // Fail closed — a broken eligibility check hides the button.
            isEligible = false
        }
    }
}
