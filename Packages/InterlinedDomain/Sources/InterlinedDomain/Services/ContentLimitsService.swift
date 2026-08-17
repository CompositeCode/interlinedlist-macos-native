import Foundation
import InterlinedKit

// MARK: - ContentLimitsProviding

/// The content-limits surface the App layer codes against (work-consolidation.md
/// G14). Backs the composer's live message-length validation.
///
/// `limits()` is **non-throwing by design**: callers always need a usable value
/// (the composer disables Post the moment the body exceeds the limit, so it can
/// never be left without one). Implementations therefore fall back to
/// `ContentLimits.default` rather than surfacing a fetch error.
public protocol ContentLimitsProviding: Sendable {
    func limits() async -> ContentLimits
}

// MARK: - ContentLimitsService

/// Fetches `GET /api/limits` and maps it to `ContentLimits`, falling back to
/// `ContentLimits.default` on any transport/decoding failure so the caller
/// always has a sensible limit to validate against.
public final class ContentLimitsService: ContentLimitsProviding {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func limits() async -> ContentLimits {
        do {
            let dto = try await api.send(Limits.get())
            return ContentLimits(from: dto)
        } catch {
            return .default
        }
    }
}
