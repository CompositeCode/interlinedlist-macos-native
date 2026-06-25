// LiveEntitlements
//
// The bridge that makes the domain `MessagesService` entitlement gate
// track the **live** signed-in account (Deliverable B / PLAN.md §8 —
// "graceful 403 → re-fetch `customerStatus`, update UI").
//
// `MessagesService` takes an `@Sendable () -> EntitlementsService`
// provider that it evaluates *at call time* on every gated write. That
// provider may run off the main actor (the service is a non-isolated
// final class), so it cannot read `CurrentUserStore.currentUser`
// directly — that is `@MainActor` state. This box is the safe hand-off:
// a lock-guarded, `Sendable` snapshot of the current `CustomerStatus`
// that the main-actor `CurrentUserStore` writes whenever the session
// resolves or changes, and the off-actor provider reads.
//
// Production wiring (in `AppEnvironment.live()`):
//   1. build the box (defaults to `.free` — signed-out / unresolved),
//   2. build `MessagesService` with a provider that reads the box,
//   3. hand the box to `CurrentUserStore` so it publishes status
//      changes into it.
//
// Decision 0003: this file lives in `App/Composition`, the composition
// root, and consumes only `InterlinedDomain`. It is never imported by a
// feature view / view model — features read `currentUserStore.currentUser`
// directly for the *UI* gate (authoritative for UX); this box is only
// the *domain backstop* source.

import Foundation
import InterlinedDomain

/// Thread-safe, `Sendable` snapshot of the live account's `CustomerStatus`.
///
/// Holds the single value the domain entitlement gate needs. Lock-guarded
/// rather than actor-isolated because the read side is the synchronous
/// `@Sendable` provider closure on `MessagesService` (it must return a value
/// without `await`).
final class LiveEntitlements: @unchecked Sendable {

    private let lock = NSLock()
    private var status: CustomerStatus

    /// Starts at `.free` — the safe default for a signed-out / not-yet-resolved
    /// session, so a real subscriber is granted features only once their status
    /// has actually resolved, and a signed-out user is never wrongly entitled.
    init(status: CustomerStatus = .free) {
        self.status = status
    }

    /// Updates the live status. Called by `CurrentUserStore` on every session
    /// state change (sign-in resolves, sign-out, mid-session `customerStatus`
    /// re-fetch after a 403). A `nil` user signals signed-out → `.free`.
    func update(user: CurrentUser?) {
        lock.lock()
        defer { lock.unlock() }
        status = user?.customerStatus ?? .free
    }

    /// The entitlements computed from the live status, evaluated at call time
    /// by the `MessagesService` provider. A pure value — no I/O.
    func current() -> EntitlementsService {
        lock.lock()
        defer { lock.unlock() }
        return EntitlementsService(customerStatus: status)
    }
}
