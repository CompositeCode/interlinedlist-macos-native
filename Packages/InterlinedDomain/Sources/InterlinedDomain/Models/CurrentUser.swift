import Foundation

/// A typed reading of the API's free-form `customerStatus` string.
///
/// The wire field is an open `String` (`UserDTO.customerStatus`) so the kit
/// stays a faithful mirror. The domain layer narrows it to the cases the app
/// gates on, preserving any unknown value under `.other` so an unexpected
/// status never silently reads as "free" or crashes a switch.
public enum CustomerStatus: Sendable, Equatable, Hashable {
    /// An active paid subscriber.
    case subscriber
    /// A free account with no active subscription.
    case free
    /// A status string the client does not yet recognise. Treated as
    /// non-subscriber for gating but preserved for display / telemetry.
    case other(String)

    /// Maps the raw wire string to a case. The set of "subscriber" values is
    /// kept deliberately small and explicit; anything else is `.other`.
    public init(raw: String) {
        switch raw.lowercased() {
        case "subscriber", "active", "subscribed", "paid":
            self = .subscriber
        case "free", "none", "inactive", "", "canceled", "cancelled":
            self = .free
        default:
            self = .other(raw)
        }
    }

    /// Whether this status grants subscriber-only features.
    public var isSubscriber: Bool {
        self == .subscriber
    }

    /// The original wire value, for display or round-tripping.
    public var rawValue: String {
        switch self {
        case .subscriber: return "subscriber"
        case .free: return "free"
        case .other(let raw): return raw
        }
    }
}

/// The full signed-in account (PLAN.md §3, §1 "Subscriber gating").
///
/// Maps from `UserDTO`. Carries the author identity (`summary`) so the same
/// projection used on message cards is reused for the current user, plus the
/// account-only fields the app needs: email, subscriber status, and the
/// optional counters the API exposes.
public struct CurrentUser: Sendable, Equatable, Identifiable {
    /// The author identity (id, username, display name, avatar).
    public let summary: UserSummary
    public let email: String
    public let customerStatus: CustomerStatus
    public let isEmailVerified: Bool
    public let isPrivateAccount: Bool
    public let createdAt: Date

    public var id: String { summary.id }
    public var username: String { summary.username }
    public var displayName: String { summary.displayName }
    public var avatarURL: URL? { summary.avatarURL }

    public init(
        summary: UserSummary,
        email: String,
        customerStatus: CustomerStatus,
        isEmailVerified: Bool,
        isPrivateAccount: Bool,
        createdAt: Date
    ) {
        self.summary = summary
        self.email = email
        self.customerStatus = customerStatus
        self.isEmailVerified = isEmailVerified
        self.isPrivateAccount = isPrivateAccount
        self.createdAt = createdAt
    }
}
