import Foundation

/// `GET /api/tags/trending` response (work-consolidation.md G20). Shape verified
/// in the gap definition: `{"tags":[{"tag","count","lastUsedAt"}…]}`.
///
/// Tolerant of a bare array as well as the named envelope, and of a missing
/// `count` / `lastUsedAt`.
public struct TrendingTagsResponse: Decodable, Sendable, Equatable {
    public let tags: [TrendingTagDTO]

    public init(tags: [TrendingTagDTO]) { self.tags = tags }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let bare = try? single.decode([TrendingTagDTO].self) {
            self.tags = bare
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tags = try c.decodeIfPresent([TrendingTagDTO].self, forKey: .tags) ?? []
    }

    private enum CodingKeys: String, CodingKey { case tags }
}

/// One trending tag with its usage count.
public struct TrendingTagDTO: Decodable, Sendable, Equatable {
    public let tag: String
    public let count: Int?
    public let lastUsedAt: Date?

    public init(tag: String, count: Int? = nil, lastUsedAt: Date? = nil) {
        self.tag = tag
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

/// `GET /api/tags/autocomplete` response — prefix matches over public messages.
///
/// **Verified live 2026-09-06:** the server returns the wrapped form,
/// `{"tags":[...]}`. The decoder still accepts a bare string array
/// (`["swift","swiftui"]`) and a bare object array (`[{"tag":"swift"}]`) as
/// well, since those cost nothing and this API has been seen to wrap some
/// collections and not others. All collapse to `[String]`.
public struct TagSuggestionsResponse: Decodable, Sendable, Equatable {
    public let tags: [String]

    public init(tags: [String]) { self.tags = tags }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if let strings = try? single.decode([String].self) {
                self.tags = strings
                return
            }
            if let objects = try? single.decode([TrendingTagDTO].self) {
                self.tags = objects.map(\.tag)
                return
            }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let strings = try? c.decodeIfPresent([String].self, forKey: .tags) ?? nil {
            self.tags = strings
            return
        }
        let objects = try c.decodeIfPresent([TrendingTagDTO].self, forKey: .tags) ?? []
        self.tags = objects.map(\.tag)
    }

    private enum CodingKeys: String, CodingKey { case tags }
}
