import Foundation
import InterlinedKit

/// The tag surface the App layer codes against (work-consolidation.md G20).
public protocol TagsServicing: Sendable {
    /// Trending tags for the timeline strip.
    func trending(limit: Int?) async throws -> [TrendingTag]
    /// Prefix completions for the composer popover.
    func suggestions(prefix: String, limit: Int?) async throws -> [String]
}

public extension TagsServicing {
    func trending() async throws -> [TrendingTag] { try await trending(limit: nil) }
    func suggestions(prefix: String) async throws -> [String] {
        try await suggestions(prefix: prefix, limit: nil)
    }
}

/// Reads `GET /api/tags/trending` and `GET /api/tags/autocomplete`.
public final class TagsService: TagsServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func trending(limit: Int?) async throws -> [TrendingTag] {
        let response = try await api.send(Tags.trending(limit: limit))
        return response.tags.map(TrendingTag.init(from:))
    }

    public func suggestions(prefix: String, limit: Int?) async throws -> [String] {
        // A blank prefix would ask the server to rank the entire tag corpus;
        // short-circuit instead of issuing a pointless request.
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response = try await api.send(
            Tags.autocomplete(prefix: TrendingTag.normalise(trimmed), limit: limit)
        )
        return response.tags.map(TrendingTag.normalise)
    }
}
