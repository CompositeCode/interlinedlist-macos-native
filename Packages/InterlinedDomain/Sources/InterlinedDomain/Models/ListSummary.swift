import Foundation

/// A list as it appears in a user's public list collection — the lightweight
/// projection the M1 browser shows in a sidebar or grid (PLAN.md §1 "Public
/// list browsing", §6 M1).
///
/// Maps from `ListDTO` rows returned by `GET /api/users/[username]/lists`.
/// That collection endpoint omits per-list detail (schema, row count) so this
/// shape only carries what the public browse view needs: identity, title,
/// description, visibility, timestamps. Use `ListDetail` for the single-list
/// view that includes the schema string.
public struct ListSummary: Sendable, Equatable, Hashable, Identifiable {
    /// The list's stable id (slug or uuid depending on API path used). The
    /// public browse routes accept either an id or a slug as the path
    /// component, so this is treated as an opaque string identifier.
    public let id: String
    public let title: String
    /// The description blurb, when set on the list.
    public let description: String?
    /// `nil` when the collection row omits the field. The public browse routes
    /// only return public lists, so this defaults to `.public` in mapping when
    /// the API does not include the flag.
    public let visibility: Visibility
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        title: String,
        description: String? = nil,
        visibility: Visibility = .public,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One page of a public-list browse: the summaries plus the next-page cursor.
///
/// Mirrors `TimelinePage` precisely so the App layer's infinite-scroll
/// machinery is shared across feature areas.
public struct ListsPage: Sendable, Equatable {
    public let lists: [ListSummary]
    public let hasMore: Bool
    public let nextOffset: Int?

    public init(lists: [ListSummary], hasMore: Bool, nextOffset: Int?) {
        self.lists = lists
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// An empty page with no further results — the boundary value used when a
    /// user has no public lists.
    public static let empty = ListsPage(lists: [], hasMore: false, nextOffset: nil)
}
