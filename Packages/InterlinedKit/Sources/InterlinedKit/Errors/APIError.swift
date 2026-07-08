import Foundation

/// Errors surfaced by the InterlinedList API layer.
///
/// The InterlinedList API uses a small, consistent convention (see the live
/// docs at `https://interlinedlist.com/help/api`):
///
/// - Non-2xx responses carry a JSON body of the shape `{ "error": "message" }`.
/// - Authentication failures return `401 Unauthorized`.
/// - Authorization / gating failures return `403 Forbidden` and the body
///   commonly explains *why* — e.g. "email not verified" or
///   "subscriber feature". Callers should preserve and surface that message.
/// - `404 Not Found` for missing resources, `400 Bad Request` for client
///   input issues, `500 Internal Server Error` for upstream failures.
///
/// `APIError` is the single error type any consumer of `APIClient` needs to
/// handle. External errors (transport failures, decode failures) are mapped
/// to one of these cases at the boundary.
public enum APIError: Error, Sendable {
    /// A network-level failure: connection refused, DNS, timeout, TLS, etc.
    /// Carries the underlying message so callers can decide whether to
    /// retry, fall back to cache, or surface a "you're offline" UI.
    case transport(message: String)

    /// The response body could not be decoded into the expected type.
    /// Carries the type description and the underlying decoder message.
    case decoding(type: String, message: String)

    /// `401 Unauthorized` — credentials are missing, malformed, or revoked.
    /// The bearer token may be invalid; callers should typically clear the
    /// session and route to onboarding.
    case unauthorized(serverMessage: String?)

    /// `403 Forbidden` — the request was authenticated but is not permitted.
    /// On InterlinedList this is also used for "email not verified" and
    /// "subscriber feature" gating; the server message is the canonical
    /// human explanation and must be preserved verbatim for UI display.
    case forbidden(serverMessage: String?)

    /// `404 Not Found`.
    case notFound(serverMessage: String?)

    /// `400 Bad Request` — request body / query failed server validation.
    case badRequest(serverMessage: String?)

    /// `429 Too Many Requests` — rate limit. The backend emits
    /// `RateLimit-Limit`, `RateLimit-Remaining`, and `RateLimit-Reset` on
    /// selected routes; `Retry-After` (seconds) may accompany a 429.
    /// Both are optional — their absence must not be treated as an error.
    /// The `retryAfter` delay is used by `RetryPolicy.rateLimit(maxDelay:)`.
    case rateLimited(serverMessage: String?, retryAfter: TimeInterval?)

    /// Any other non-2xx status code, with the decoded server message if
    /// the body matched the `{error}` shape.
    case httpStatus(code: Int, serverMessage: String?)
}

extension APIError: Equatable {
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case let (.transport(a), .transport(b)):
            return a == b
        case let (.decoding(aT, aM), .decoding(bT, bM)):
            return aT == bT && aM == bM
        case let (.unauthorized(a), .unauthorized(b)):
            return a == b
        case let (.forbidden(a), .forbidden(b)):
            return a == b
        case let (.notFound(a), .notFound(b)):
            return a == b
        case let (.badRequest(a), .badRequest(b)):
            return a == b
        case let (.rateLimited(aM, aR), .rateLimited(bM, bR)):
            return aM == bM && aR == bR
        case let (.httpStatus(aC, aM), .httpStatus(bC, bM)):
            return aC == bC && aM == bM
        default:
            return false
        }
    }
}

extension APIError: LocalizedError, CustomStringConvertible {
    /// The server-supplied human message if one is available, otherwise a
    /// concise developer-facing description of the case. Suitable for both
    /// `NSAlert` body text and `os.Logger` output.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .transport(let message):
            return "Network error: \(message)"
        case .decoding(let type, let message):
            return "Decoding \(type) failed: \(message)"
        case .unauthorized(let message):
            return message ?? "Unauthorized"
        case .forbidden(let message):
            return message ?? "Forbidden"
        case .notFound(let message):
            return message ?? "Not found"
        case .badRequest(let message):
            return message ?? "Bad request"
        case .rateLimited(let message, _):
            return message ?? "Rate limited"
        case .httpStatus(let code, let message):
            return message ?? "HTTP \(code)"
        }
    }
}

extension APIError {
    /// The HTTP status code associated with the case, if any. Useful for
    /// telemetry and retry/backoff policies. Returns `nil` for purely
    /// client-side cases (`transport`, `decoding`).
    public var httpStatusCode: Int? {
        switch self {
        case .transport, .decoding: return nil
        case .unauthorized: return 401
        case .forbidden: return 403
        case .notFound: return 404
        case .badRequest: return 400
        case .rateLimited: return 429
        case .httpStatus(let code, _): return code
        }
    }

    /// Maps an HTTP status code + a (possibly nil) decoded server message
    /// into the most specific `APIError` case. Used by `APIClient` after it
    /// extracts `{error: "..."}` from the response body. Public so endpoint
    /// builders and tests can use the exact same mapping.
    public static func from(
        statusCode: Int,
        serverMessage: String?,
        retryAfter: TimeInterval? = nil
    ) -> APIError {
        switch statusCode {
        case 400: return .badRequest(serverMessage: serverMessage)
        case 401: return .unauthorized(serverMessage: serverMessage)
        case 403: return .forbidden(serverMessage: serverMessage)
        case 404: return .notFound(serverMessage: serverMessage)
        case 429: return .rateLimited(serverMessage: serverMessage, retryAfter: retryAfter)
        default:  return .httpStatus(code: statusCode, serverMessage: serverMessage)
        }
    }
}

/// Decoded body shape for InterlinedList error responses: `{ "error": "…" }`.
///
/// Internal to the kit, but exposed so endpoint builders and tests can decode
/// the same envelope when they need to inspect it.
public struct APIErrorBody: Decodable, Sendable, Equatable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}
