// CurrentUserStore
//
// App-layer adapter that bridges the actor-based domain `SessionManaging`
// surface into a SwiftUI-friendly `@Observable` source views can read
// synchronously (PLAN.md §3 — UI binds to domain protocols; the App
// layer is the only place that bridges actor state into rendering).
//
// The Timeline and Detail views ask `CurrentUserStore.currentUserID`
// when deciding whether to show the Edit / Delete menu items on a
// message row. Per the M2 ownership-gating rule, when no `Session.user`
// has resolved yet (sign-in not yet completed, or session restoration
// in flight) the store returns `nil` and the views hide the menu items
// — never "enabled but broken".
//
// Construction never blocks: `start()` spawns a detached task that
// subscribes to `SessionManaging.states` and mirrors every state change
// into the published `currentUser`. A separate `restore()` entry point
// lets the App perform the initial token-restore round-trip at launch
// without coupling that I/O to the store's lifecycle.
//
// Decision 0003 (App-layer Kit-import policy): this file consumes only
// `InterlinedDomain`. The Kit-level token store / API client are wired
// behind `SessionService` and never surface here.

import Foundation
import Observation
import InterlinedDomain

/// Reads-only, App-layer projection of the current session. Views bind
/// to `currentUser` and `currentUserID` directly; mutation happens via
/// the underlying `SessionManaging` service (sign-in / sign-out flows
/// owned by the Onboarding milestone, M0/M7).
@MainActor
@Observable
final class CurrentUserStore {

    /// The injected domain session. Held as the protocol so tests
    /// substitute a stub without touching networking or actors.
    private let session: SessionManaging

    /// Optional live-entitlements box the domain `MessagesService` gate reads
    /// (Deliverable B / PLAN.md §8). When present, every resolved session state
    /// publishes its `customerStatus` here so the off-actor domain gate tracks
    /// the live account. `nil` in tests that don't exercise the domain backstop.
    private let liveEntitlements: LiveEntitlements?

    /// The signed-in account, or `nil` when signed out / not yet
    /// resolved. The Timeline / Detail views gate edit / delete on
    /// this being non-nil and matching the message author.
    private(set) var currentUser: CurrentUser?

    /// Convenience accessor used by ownership-check sites so the call
    /// site stays a one-liner (`store.currentUserID == message.author.id`).
    var currentUserID: String? { currentUser?.id }

    /// Convenience accessor for the signed-in username. Mirrors
    /// `currentUserID`; both are kept here so views don't reach into
    /// `currentUser?.summary.username` themselves.
    var currentUsername: String? { currentUser?.username }

    /// Owns the long-lived subscription to `session.states`. Lives on
    /// the main actor (the rest of this class does). The loop captures
    /// `self` weakly so the iteration ends naturally when the store
    /// deallocates; an explicit `deinit`-time cancel would have to
    /// reach into main-actor state from a `nonisolated` context, which
    /// the Observation macro does not permit on a stored property.
    private var subscription: Task<Void, Never>?

    init(session: SessionManaging, liveEntitlements: LiveEntitlements? = nil) {
        self.session = session
        self.liveEntitlements = liveEntitlements
    }

    /// Subscribes to the session state stream. Safe to call multiple
    /// times — re-subscribing replaces the prior task. Returns
    /// immediately; the first state arrives asynchronously.
    func start() {
        subscription?.cancel()
        // `session.states` is `nonisolated` and synchronous to read.
        // The values it yields arrive on whatever context the
        // underlying actor / continuation runs on; we hop back to the
        // main actor inside `apply` so the published `currentUser`
        // change is UI-thread-safe.
        let stream = session.states
        subscription = Task { @MainActor [weak self] in
            for await state in stream {
                guard let self else { return }
                self.apply(state)
            }
        }
    }

    /// Convenience for M2 launch wiring: triggers token-restore,
    /// folds the result into `currentUser` synchronously (so the UI
    /// has the gated state ready as soon as `restore` returns), and
    /// surfaces any error to the caller. The state stream — when
    /// `start()` has been called — yields the same state too, so
    /// later changes (e.g. sign-out) flow through the stream path.
    @discardableResult
    func restore() async throws -> SessionState {
        let state = try await session.restore()
        apply(state)
        return state
    }

    /// Applied on the main actor so the published `currentUser` change
    /// stays UI-thread-safe. Also publishes the live `customerStatus` into
    /// the entitlements box (when wired) so the off-actor domain gate
    /// re-evaluates against the current account on its next call.
    private func apply(_ state: SessionState) {
        currentUser = state.currentUser
        liveEntitlements?.update(user: state.currentUser)
    }
}
