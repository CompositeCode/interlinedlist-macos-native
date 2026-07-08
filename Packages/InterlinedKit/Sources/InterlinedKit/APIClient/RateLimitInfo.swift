import Foundation

/// Structured representation of the `RateLimit-Limit`, `RateLimit-Remaining`,
/// and `RateLimit-Reset` response headers.
///
/// The backend emits these headers selectively — currently only on
/// `POST /api/messages` and `POST /api/documents/sync`. All other routes omit
/// them entirely. Callers must treat absent headers as "no limit enforced on
/// this route" rather than as an error or a warning.
///
/// Use ``parse(from:)`` to extract info from an `HTTPURLResponse`. It returns
/// `nil` when the mandatory limit and remaining headers are absent, so callers
/// can guard cleanly:
///
/// ```swift
/// guard let info = RateLimitInfo.parse(from: response) else {
///     // No limit enforced on this route — proceed at full pace.
///     return
/// }
/// // Apply pacing: check info.remaining, schedule around info.resetAt, etc.
/// ```
public struct RateLimitInfo: Sendable, Equatable {

    /// The total requests allowed per window (`RateLimit-Limit`).
    public let limit: Int

    /// Requests remaining in the current window (`RateLimit-Remaining`).
    public let remaining: Int

    /// When the current window resets, derived from `RateLimit-Reset`
    /// (a Unix-epoch integer in seconds). `nil` when the header is absent
    /// or non-numeric — callers must not rely on this field being set.
    public let resetAt: Date?

    public init(limit: Int, remaining: Int, resetAt: Date? = nil) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
    }

    // MARK: - Parsing

    /// Parses `RateLimit-Limit`, `RateLimit-Remaining`, and `RateLimit-Reset`
    /// from `response`.
    ///
    /// Returns `nil` when **either** `RateLimit-Limit` **or**
    /// `RateLimit-Remaining` is absent or non-numeric — the parse is entirely
    /// non-fatal and never logs a warning. The caller must interpret `nil` as
    /// "no limit enforced on this route".
    ///
    /// `RateLimit-Reset` is treated as optional within a valid rate-limit
    /// envelope: its absence yields a `RateLimitInfo` with `resetAt == nil`.
    public static func parse(from response: HTTPURLResponse) -> RateLimitInfo? {
        guard
            let limitStr = response.value(forHTTPHeaderField: "RateLimit-Limit"),
            let limit = Int(limitStr),
            let remainingStr = response.value(forHTTPHeaderField: "RateLimit-Remaining"),
            let remaining = Int(remainingStr)
        else {
            return nil
        }

        let resetAt: Date?
        if let resetStr = response.value(forHTTPHeaderField: "RateLimit-Reset"),
           let epochSeconds = TimeInterval(resetStr) {
            resetAt = Date(timeIntervalSince1970: epochSeconds)
        } else {
            resetAt = nil
        }

        return RateLimitInfo(limit: limit, remaining: remaining, resetAt: resetAt)
    }
}
