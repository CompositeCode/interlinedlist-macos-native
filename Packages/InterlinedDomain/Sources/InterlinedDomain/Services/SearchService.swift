import Foundation
import InterlinedKit

// MARK: - SearchResults

/// The combined result of a global search (the-gaps.md G5). Each resource is
/// searched independently; the App surface groups them under one search field.
public struct SearchResults: Sendable, Equatable {
    public var messages: [Message]
    public var lists: [ListSummary]
    public var documents: [Document]

    public init(messages: [Message] = [], lists: [ListSummary] = [], documents: [Document] = []) {
        self.messages = messages
        self.lists = lists
        self.documents = documents
    }

    /// `true` when no resource returned a hit.
    public var isEmpty: Bool { messages.isEmpty && lists.isEmpty && documents.isEmpty }

    /// Total hit count across all three resources.
    public var totalCount: Int { messages.count + lists.count + documents.count }

    public static let empty = SearchResults()
}

// MARK: - SearchServicing

/// The search surface the App layer codes against — full-text search over the
/// current user's messages, lists, and documents (the-gaps.md G5).
///
/// Follows the domain-service DI shape: takes its `APIClientProtocol` as a
/// parameter so unit tests run against a stub. Per decision 0003 the App layer
/// never sees the kit DTOs — this service returns domain values (`Message`,
/// `ListSummary`, `Document`) mapped through the existing per-resource mappers.
///
/// A blank/whitespace-only query short-circuits to an empty result **without**
/// hitting the network — the global search field calls these on every keystroke,
/// so an empty term must not fan out three pointless requests.
public protocol SearchServicing: Sendable {
    func messages(query: String, limit: Int, offset: Int) async throws -> [Message]
    func lists(query: String, limit: Int, offset: Int) async throws -> [ListSummary]
    func documents(query: String, limit: Int, offset: Int) async throws -> [Document]
}

public extension SearchServicing {
    /// Convenience overloads with the default page size (20).
    func messages(query: String) async throws -> [Message] {
        try await messages(query: query, limit: 20, offset: 0)
    }
    func lists(query: String) async throws -> [ListSummary] {
        try await lists(query: query, limit: 20, offset: 0)
    }
    func documents(query: String) async throws -> [Document] {
        try await documents(query: query, limit: 20, offset: 0)
    }

    /// Searches all three resources concurrently and merges the hits. A blank
    /// query returns `.empty` without any request. If any leg fails the whole
    /// call throws — the App layer can fall back to per-tab searches when it
    /// needs partial results.
    func all(query: String, limit: Int = 20) async throws -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        async let messages = self.messages(query: trimmed, limit: limit, offset: 0)
        async let lists = self.lists(query: trimmed, limit: limit, offset: 0)
        async let documents = self.documents(query: trimmed, limit: limit, offset: 0)
        return SearchResults(
            messages: try await messages,
            lists: try await lists,
            documents: try await documents
        )
    }
}

// MARK: - SearchService

public final class SearchService: SearchServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func messages(query: String, limit: Int, offset: Int) async throws -> [Message] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let dto = try await api.send(Search.messages(query: trimmed, limit: limit, offset: offset))
        return dto.messages.map(Message.init(from:))
    }

    public func lists(query: String, limit: Int, offset: Int) async throws -> [ListSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let dto = try await api.send(Search.lists(query: trimmed, limit: limit, offset: offset))
        return dto.lists.map(ListSummary.init(from:))
    }

    public func documents(query: String, limit: Int, offset: Int) async throws -> [Document] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let dto = try await api.send(Search.documents(query: trimmed, limit: limit, offset: offset))
        return dto.documents.map(Document.init(from:))
    }
}
