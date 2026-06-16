import Foundation

/// A single seam for adding retry / backoff behaviour to `APIClient`.
///
/// PLAN.md §8 notes that the API does not currently document rate-limit
/// headers, so v1 ships with `.none`. When a policy is needed, swap it at
/// construction time — `APIClient` calls into this on every non-2xx error
/// and respects whatever delay it returns.
public struct RetryPolicy: Sendable {

    /// `(error, attemptNumber) -> delay-or-nil`. Return a non-nil
    /// `TimeInterval` to retry after that many seconds; return `nil` to
    /// stop retrying and surface the error.
    public let delay: @Sendable (APIError, Int) -> TimeInterval?

    public init(delay: @escaping @Sendable (APIError, Int) -> TimeInterval?) {
        self.delay = delay
    }

    /// No retry — every error surfaces immediately. The default.
    public static let none = RetryPolicy { _, _ in nil }

    /// Retry on 429 once, after the server-supplied `Retry-After` (capped
    /// at `maxDelay`). All other errors surface immediately.
    public static func rateLimit(maxDelay: TimeInterval = 10) -> RetryPolicy {
        RetryPolicy { error, attempt in
            guard attempt == 0,
                  case .rateLimited(_, let retryAfter) = error else {
                return nil
            }
            return min(retryAfter ?? 1, maxDelay)
        }
    }
}
