// FollowButtonViewModel
//
// Drives the M5 follow button rendered inside `ProfileHeaderView`
// (PLAN.md §1 "Follow system", §6 M5). Owns the relationship state,
// the in-flight pending operation set (to de-bounce rapid taps), and
// the optimistic state transitions documented in the swift-engineer
// skill (snapshot → optimistic mutate → service call → confirm or
// rollback).
//
// View states:
//   - `.notFollowing`   — show "Follow" button.
//   - `.pending`        — show "Requested" (greyed; tap is a no-op
//                          until the request is approved or rejected
//                          server-side).
//   - `.following`      — show "Following" with hover-to-show
//                          "Unfollow".
//   - `nil` userID      — render nothing (the current user's own
//                          profile, or no session yet).
//
// Per decision 0003 (App-layer Kit-import policy), this view model
// reads relationship state through `FollowRelationshipReading`
// (a protocol whose concrete impl lives in `App/Composition/`) and
// performs follow / unfollow writes through `SocialServicing`. The
// view model itself imports only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class FollowButtonViewModel {

    // MARK: - Dependencies

    private let social: SocialServicing
    private let reader: FollowRelationshipReading

    // MARK: - Identity

    /// The user being followed. `nil` when the view model is rendered
    /// for the current user's own profile or before any profile has
    /// been loaded — the button hides itself in that case.
    private(set) var targetUserID: String?

    /// True when `targetUserID` matches the signed-in user. The button
    /// hides itself for self-profiles (PLAN.md §6 M2 ownership-gating
    /// rule: never "enabled but broken").
    private(set) var isSelf: Bool = false

    // MARK: - Observable state

    /// The current relationship. `nil` until the first successful
    /// `relationship(with:)` call. The button renders nothing while
    /// state is unknown to avoid flickering a wrong-state affordance.
    private(set) var relationship: FollowRelationship?

    /// True while a follow / unfollow round-trip is in flight. The
    /// button shows a progress spinner and disables itself.
    private(set) var isMutating: Bool = false

    /// True while the initial relationship read is in flight. Separate
    /// from `isMutating` so the view can show a different chrome (or
    /// hide the button entirely) during the bootstrap fetch.
    private(set) var isLoading: Bool = false

    /// The most recent error from a follow / unfollow round-trip. The
    /// view surfaces this as a transient toast / inline message; it
    /// clears on the next successful round-trip.
    private(set) var error: Error?

    // MARK: - Init

    init(
        social: SocialServicing,
        reader: FollowRelationshipReading
    ) {
        self.social = social
        self.reader = reader
    }

    // MARK: - Intents

    /// Configures the view model for a specific target user and
    /// triggers the initial relationship read. Bound to the profile
    /// load completion in `ProfileViewModel`. `currentUserID == nil`
    /// keeps the button hidden (session not yet resolved per the
    /// M2 ownership-gating rule).
    ///
    /// - Parameters:
    ///   - targetUserID: the user the button acts on.
    ///   - currentUserID: the signed-in user (from
    ///     `CurrentUserStore`). `nil` when no session has resolved
    ///     yet — the button hides itself.
    func configure(targetUserID: String, currentUserID: String?) async {
        self.targetUserID = targetUserID
        // Self-profile check: hide the button when the target is the
        // signed-in user. Done before any network call so we never
        // round-trip for a button that won't render.
        let isSelf = currentUserID == targetUserID
        self.isSelf = isSelf
        guard !isSelf else {
            relationship = nil
            return
        }
        await loadRelationship()
    }

    /// Re-reads the relationship state from the server. Used after a
    /// pending-request transition (the server moved approval) so the
    /// button refreshes to "Following".
    func refresh() async {
        guard targetUserID != nil, !isSelf else { return }
        await loadRelationship()
    }

    /// Tapped — performs the action implied by the current state:
    ///   - `.notFollowing`  → follow (may transition to `.following`
    ///                         or `.pending` depending on the target's
    ///                         privacy).
    ///   - `.pending`       → no-op (the request is awaiting approval).
    ///   - `.following`     → unfollow.
    ///
    /// Optimistic UI per the swift-engineer skill: snapshot the prior
    /// relationship, mutate locally, call the service, and on success
    /// replace the optimistic copy with the server-authoritative state.
    /// On failure restore the snapshot and surface the error.
    func tap() async {
        guard let targetUserID, !isSelf, !isMutating else { return }
        guard let snapshot = relationship else { return }
        switch snapshot.state {
        case .notFollowing:
            await performFollow(targetUserID: targetUserID, snapshot: snapshot)
        case .pending:
            // Pending requests are awaiting server-side approval; the
            // button is a no-op here (it renders greyed). Surfaced
            // explicitly so future intents (cancel request) have a
            // clear extension point.
            return
        case .following:
            await performUnfollow(targetUserID: targetUserID, snapshot: snapshot)
        }
    }

    /// Clears the surfaced error. Bound to a tap-to-dismiss affordance
    /// in the view; also used by tests that want to assert the error
    /// state was set then cleared.
    func clearError() {
        error = nil
    }

    // MARK: - Internals

    private func loadRelationship() async {
        guard let targetUserID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            relationship = try await reader.relationship(with: targetUserID)
        } catch {
            self.error = error
            // Leave `relationship` at its prior value (nil on first
            // load). The view renders nothing in that case, which is
            // the safe default.
        }
    }

    private func performFollow(targetUserID: String, snapshot: FollowRelationship) async {
        // Optimistic flip: assume the target is public and the follow
        // becomes immediately live. If the server resolves to pending
        // (private account) the success path overwrites with the
        // authoritative state.
        relationship = FollowRelationship(
            isFollowing: true,
            isFollowedBy: snapshot.isFollowedBy,
            hasPendingRequest: false
        )
        isMutating = true
        defer { isMutating = false }
        do {
            let action = try await social.follow(userId: targetUserID)
            switch action {
            case .approved:
                relationship = FollowRelationship(
                    isFollowing: true,
                    isFollowedBy: snapshot.isFollowedBy,
                    hasPendingRequest: false
                )
            case .pending:
                relationship = FollowRelationship(
                    isFollowing: false,
                    isFollowedBy: snapshot.isFollowedBy,
                    hasPendingRequest: true
                )
            }
            error = nil
        } catch {
            // Rollback the optimistic flip and surface the error.
            relationship = snapshot
            self.error = error
        }
    }

    private func performUnfollow(targetUserID: String, snapshot: FollowRelationship) async {
        // Optimistic flip: assume the unfollow succeeds.
        relationship = FollowRelationship(
            isFollowing: false,
            isFollowedBy: snapshot.isFollowedBy,
            hasPendingRequest: false
        )
        isMutating = true
        defer { isMutating = false }
        do {
            try await social.unfollow(userId: targetUserID)
            error = nil
        } catch {
            relationship = snapshot
            self.error = error
        }
    }
}
