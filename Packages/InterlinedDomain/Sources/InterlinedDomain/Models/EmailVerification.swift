import Foundation

/// The resend-verification-email affordance (GitHub #41 / work-consolidation.md G38).
///
/// ## Why this deep-links instead of calling the API
///
/// `POST /api/auth/send-verification-email` is declared `x-auth-type: session`
/// in the live OpenAPI document (confirmed 2026-09-09; it is one of 45
/// session-only operations, against 187 `sync-token` ones). This client
/// authenticates with a Bearer sync-token and therefore **cannot** call it —
/// shipping a button that silently 401s is exactly what issue #41 rules out.
///
/// So the resend action opens the web Settings ▸ Security page, where the user
/// already has a session. If the route is ever opened to Bearer, replace
/// ``resendURL(baseURL:)`` with a real kit request builder; the cooldown model
/// below is unaffected either way.
public struct EmailVerificationResend: Sendable, Equatable {

    /// The documented rate limit: *"You can resend once every 10 minutes."*
    public static let cooldown: TimeInterval = 600

    /// The default web origin for the deep link.
    public static let defaultWebBaseURL = URL(string: "https://interlinedlist.com")!

    /// When the user last triggered a resend from this client, or `nil` if they
    /// have not during this install.
    ///
    /// **Advisory only.** The server owns the real limit and counts resends the
    /// user triggered on the web too, so a local `nil` does not prove a resend
    /// will be accepted. The value exists so the UI can avoid *obviously*
    /// wasted trips and tell the user when to come back.
    public let lastResendAt: Date?

    public init(lastResendAt: Date? = nil) {
        self.lastResendAt = lastResendAt
    }

    /// Seconds still to wait before another resend is worth attempting.
    ///
    /// Clamped at zero, so a `lastResendAt` in the future — a clock change, or
    /// a value restored from a device whose clock has since moved back — yields
    /// a finite wait rather than a negative one or a crash.
    public func remainingCooldown(now: Date = Date()) -> TimeInterval {
        guard let lastResendAt else { return 0 }
        let elapsed = now.timeIntervalSince(lastResendAt)
        guard elapsed.isFinite else { return 0 }
        return max(0, min(Self.cooldown, Self.cooldown - elapsed))
    }

    /// Whether a resend is worth attempting now.
    public func isAvailable(now: Date = Date()) -> Bool {
        remainingCooldown(now: now) == 0
    }

    /// When the next resend becomes available, or `nil` if it already is.
    public func availableAt(now: Date = Date()) -> Date? {
        let remaining = remainingCooldown(now: now)
        return remaining == 0 ? nil : now.addingTimeInterval(remaining)
    }

    /// The web page that can actually perform the resend.
    public func resendURL(baseURL: URL = defaultWebBaseURL) -> URL {
        baseURL.appendingPathComponent("settings")
    }

    /// Returns a copy stamped with a resend at `now`.
    public func recordingResend(at now: Date = Date()) -> EmailVerificationResend {
        EmailVerificationResend(lastResendAt: now)
    }
}

/// The web pages this client hands the user off to when a remedy cannot be
/// performed natively (GitHub #40 / #41 / #42).
///
/// Verified live 2026-09-09: `/support` and `/help` answer 200; `/settings`
/// answers 200 for a signed-in browser and redirects anonymous visitors to
/// `/login`. `/contact` does **not** exist (404) — do not link to it.
public enum AccountWebDestination: Sendable, Equatable, Hashable, CaseIterable {

    /// Settings, where "Resend verification email" and the subscription
    /// controls live. The resend route is session-only, so this is the only
    /// way a Bearer client can offer it.
    case settings

    /// The appeal path for a restricted or suspended account.
    case support

    /// The help centre.
    case help

    public var path: String {
        switch self {
        case .settings: return "settings"
        case .support: return "support"
        case .help: return "help"
        }
    }

    public func url(baseURL: URL = EmailVerificationResend.defaultWebBaseURL) -> URL {
        baseURL.appendingPathComponent(path)
    }
}

public extension CapabilityRemedy {
    /// The page that resolves this remedy, or `nil` when there is nothing the
    /// user can do (a closed account).
    ///
    /// Subscription is managed on the web — there is no native purchase path.
    var webDestination: AccountWebDestination? {
        switch self {
        case .verifyEmail: return .settings
        case .contactSupport: return .support
        case .upgrade: return .settings
        case .noneAvailable: return nil
        }
    }
}
