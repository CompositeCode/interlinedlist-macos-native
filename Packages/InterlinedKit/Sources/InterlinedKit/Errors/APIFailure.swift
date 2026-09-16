import Foundation

/// An HTTP failure **with its response body intact** (GitHub #103).
///
/// `APIError` keeps only the decoded `{error}` string; everything else in the
/// body is discarded before any caller sees it. That is fine for the
/// overwhelming majority of failures, where a sentence is all the UI needs — and
/// wrong for the handful where the server answers a *question* rather than
/// reporting a malfunction:
///
/// - `PUT /api/lists/{id}/schema` refuses a destructive rebuild with `400` plus
///   a **`propertiesWithData` array naming the columns** that still hold data.
///   The UI should name them and offer the confirmation; without the body it can
///   only repeat the server's sentence.
/// - The app-settings family is compare-and-set: a stale `baseVersion` answers
///   `409` with the **`current` document attached**, so a client can show what
///   changed, merge, or re-base and retry.
///
/// ## Why this is a separate type rather than a case on `APIError`
///
/// `APIError`'s cases carry a single `serverMessage` associated value, and
/// **420 sites across 78 files** pattern-match or construct them. Adding a
/// second associated value is a mechanical change to every one of those,
/// including every test — enormous churn, and every line of it a chance to get
/// a case wrong, in service of two call sites.
///
/// So this is **opt-in**: `sendCapturingFailure(_:)` throws an `APIFailure`, and
/// only the callers that actually need the body use it. Every other call site
/// keeps throwing and catching plain `APIError`, unchanged.
///
/// - Important: an `APIFailure` is **not** an `APIError`, so `catch let error as
///   APIError` will not match it. That is deliberate — a caller opts into the
///   richer error by choosing the richer send. `underlyingError` and the
///   forwarded `localizedDescription` mean nothing is lost if it reaches generic
///   error-display code.
public struct APIFailure: Error, Sendable {

    /// The failure as `APIError` models it. Callers that only care about the
    /// status or the message switch on this exactly as they would have.
    public let underlyingError: APIError

    /// The raw response body, when the failure carried one.
    ///
    /// `nil` for a transport failure, which never had a body to keep.
    public let body: Data?

    public init(underlyingError: APIError, body: Data?) {
        self.underlyingError = underlyingError
        self.body = body
    }

    /// Decodes the body as `T`, or `nil` when it was absent or did not match.
    ///
    /// Returning `nil` rather than throwing is the point: a caller asking for
    /// details is asking an **optional** question, and a decode failure here
    /// must degrade to today's behaviour — a message with no details — rather
    /// than masking the original error with a decoding one. The failure the
    /// caller is handling is the HTTP failure, not this.
    public func details<T: Decodable>(as type: T.Type) -> T? {
        guard let body else { return nil }
        return try? JSONCoders.makeDecoder().decode(T.self, from: body)
    }

    /// The HTTP status, when there was one.
    public var httpStatusCode: Int? { underlyingError.httpStatusCode }
}

extension APIFailure: LocalizedError, CustomStringConvertible {
    /// Forwarded, so an `APIFailure` that reaches generic error-display code
    /// reads exactly as the `APIError` would have. Nothing regresses by opting
    /// in to the richer send.
    public var errorDescription: String? { underlyingError.errorDescription }
    public var description: String { underlyingError.description }
}
