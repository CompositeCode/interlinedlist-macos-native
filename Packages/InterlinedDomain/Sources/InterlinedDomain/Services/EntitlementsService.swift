import Foundation

/// A subscriber-gated capability (PLAN.md §1, §6 M6 — "Subscriber & orgs").
///
/// Seeded with the three features the plan names as subscriber-only. Free
/// features are simply absent from this enum; if every `Feature` is
/// subscriber-gated, the gating switch is exhaustive by construction.
public enum Feature: Sendable, Equatable, Hashable, CaseIterable {
    /// Media attachments on a post (PLAN.md §1 "Media attachments").
    case mediaAttachments
    /// Scheduling a post for future publication (PLAN.md §1 "Scheduled posts").
    case scheduledPosts
    /// Cross-posting to Mastodon / Bluesky / LinkedIn (PLAN.md §1 "Cross-posting").
    case crossPosting
}

/// Maps the current account's `customerStatus` to feature flags so gating is
/// "one switch, not scattered ifs" (PLAN.md §3). Pure value type — give it a
/// `CurrentUser` and ask; no I/O, no async.
///
/// When the signed-in user's subscription state changes, the App layer rebuilds
/// the service from the refreshed `CurrentUser` (e.g. after a 403 triggers a
/// `customerStatus` re-fetch, per PLAN.md §8).
public struct EntitlementsService: Sendable, Equatable {

    /// The account these entitlements are computed for. `nil` represents a
    /// signed-out / unknown user, which is treated as a non-subscriber.
    private let customerStatus: CustomerStatus

    /// Stored override for `canManageLists`. `nil` defers to the default
    /// (permissive in M3 — see doc on the public property). Settable only
    /// at construction so the value stays a true pure value type.
    private let listManagementOverride: Bool?

    public init(user: CurrentUser?) {
        self.customerStatus = user?.customerStatus ?? .free
        self.listManagementOverride = nil
    }

    /// Direct construction from a status, for tests and for callers that only
    /// hold the status.
    public init(customerStatus: CustomerStatus) {
        self.customerStatus = customerStatus
        self.listManagementOverride = nil
    }

    /// Construct with an explicit list-management gate. Used by tests today
    /// (to exercise the `ListsError.subscriberRequired` path against the M3
    /// permissive default) and by the M6 wave when the real gate source
    /// becomes known. The default factories above keep the permissive M3
    /// behaviour for everyone else.
    public init(customerStatus: CustomerStatus, canManageLists: Bool) {
        self.customerStatus = customerStatus
        self.listManagementOverride = canManageLists
    }

    /// Whether the account is an active paid subscriber.
    public var isSubscriber: Bool {
        customerStatus.isSubscriber
    }

    /// Whether `feature` is available to the current account. The single switch
    /// every gated call site routes through.
    public func isEnabled(_ feature: Feature) -> Bool {
        switch feature {
        case .mediaAttachments, .scheduledPosts, .crossPosting:
            return isSubscriber
        }
    }

    /// Whether the current account may manage lists (create, edit, share,
    /// delete, mutate rows, edit schemas, manage connections).
    ///
    /// **M3 defensive gate.** PLAN.md §6 M6 ships the real subscriber-driven
    /// gating logic. Until then the M3 lists service must call through a
    /// single entitlement seam so the call sites are correct on day one and
    /// the M6 wave only has to flip this property's default. The default
    /// behaviour is permissive — every signed-in account "may manage lists"
    /// — but the call shape (and the `ListsError.subscriberRequired` error
    /// path) is the production shape from M3 onward.
    ///
    /// When M6 lands, change the default in this property's body to
    /// `isSubscriber` (or to the per-feature check the upstream entitlement
    /// model dictates) without touching any call site in `ListsService`.
    /// Tests that need to exercise the blocked-path use
    /// `init(customerStatus:canManageLists:)` to override the default.
    public var canManageLists: Bool {
        // Defensive default: permissive in M3. Override-aware so tests can
        // exercise the blocked path without waiting for M6.
        listManagementOverride ?? true
    }
}
