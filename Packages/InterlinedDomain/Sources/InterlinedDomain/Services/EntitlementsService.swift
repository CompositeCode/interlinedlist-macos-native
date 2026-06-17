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

    public init(user: CurrentUser?) {
        self.customerStatus = user?.customerStatus ?? .free
    }

    /// Direct construction from a status, for tests and for callers that only
    /// hold the status.
    public init(customerStatus: CustomerStatus) {
        self.customerStatus = customerStatus
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
}
