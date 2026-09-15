import Foundation

/// The full editable list shape the M3 lists UI works against
/// (PLAN.md §1 "Structured lists", §6 M3).
///
/// Distinct from M1's read-only `ListSummary` / `ListDetail`:
/// - `ListSummary` / `ListDetail` map the **public** browse routes
///   (`/api/users/[username]/lists*`) — no schema editor, no watchers,
///   no row mutation. Those types stay in place for the M1 read-only UI.
/// - `OwnedList` maps the **authenticated** routes (`/api/lists*`) — the
///   list-as-managed-by-its-owner shape that powers the editor, schema DSL,
///   row CRUD, watchers, and GitHub-backed refresh.
///
/// The `schemaDescription` field carries the raw DSL string so a list can
/// be displayed before the schema parser runs; the typed `ListSchema` is
/// available through `ListsService.schema(of:)`.
public struct OwnedList: Sendable, Equatable, Hashable, Identifiable {

    /// List id (slug or uuid — opaque to the client).
    public let id: String

    /// List title.
    public let title: String

    /// Description blurb. `nil` when the list has none set.
    public let description: String?

    /// Visibility. The owned routes return `isPublic` on every row.
    public let visibility: Visibility

    /// A one-line rendering of the columns, in the client's DSL spelling, for
    /// surfaces that show a list's shape without opening the editor.
    ///
    /// This used to be read straight off `ListDTO.schema` — a wire field the
    /// server has **never** sent, so it was always `nil` and every surface that
    /// displayed it showed nothing (GitHub #85). It is now derived from
    /// ``schema`` when the route returned the list's columns.
    public let schemaDescription: String?

    /// The list's columns, when the route returned them.
    ///
    /// `nil` means *"this route does not carry columns"* — the lightweight
    /// collection rows do not — which is **not** the same as a list with no
    /// columns (`ListSchema.empty`). Collapsing the two would make every list in
    /// a collection page look column-less.
    public let schema: ListSchema?

    /// Parent list id for nested lists (PLAN.md §1 "Nested lists").
    public let parentID: String?

    /// GitHub-backed list metadata, when this list is GitHub-backed.
    /// `nil` for plain lists.
    public let gitHubSource: GitHubListSource?

    public let createdAt: Date?

    public let updatedAt: Date?

    public init(
        id: String,
        title: String,
        description: String? = nil,
        visibility: Visibility = .private,
        schemaDescription: String? = nil,
        schema: ListSchema? = nil,
        parentID: String? = nil,
        gitHubSource: GitHubListSource? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.visibility = visibility
        // Derive the display string from the columns when the caller supplied
        // them and no explicit string — so the two can never disagree.
        self.schemaDescription = schemaDescription ?? schema?.dslDescription
        self.schema = schema
        self.parentID = parentID
        self.gitHubSource = gitHubSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One page of owned lists — the same `*Page` shape every paginated read in
/// the domain layer uses (`TimelinePage`, `ListsPage`, `RowsPage`).
public struct OwnedListsPage: Sendable, Equatable {

    public let lists: [OwnedList]
    public let hasMore: Bool
    public let nextOffset: Int?

    public init(lists: [OwnedList], hasMore: Bool, nextOffset: Int?) {
        self.lists = lists
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// The empty page boundary value — used when the user has no lists.
    public static let empty = OwnedListsPage(lists: [], hasMore: false, nextOffset: nil)
}
