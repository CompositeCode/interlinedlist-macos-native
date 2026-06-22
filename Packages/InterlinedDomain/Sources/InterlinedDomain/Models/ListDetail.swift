import Foundation

/// The single-list public view — extends `ListSummary` with the schema DSL
/// string the M3 typed-row editor will parse (PLAN.md §1 "Structured lists",
/// §6 M3).
///
/// Maps from `ListDTO` returned by `GET /api/users/[username]/lists/[slug]`.
/// In M1 the schema is carried as the raw DSL string only — parsing it into
/// typed columns is M3 work (the schema DSL parser ships with the M3 lists
/// milestone, per PLAN.md §6 / §7). The string is exposed here so the M1 UI
/// can still surface a human-readable schema description ("Title:text,
/// Year:number") above the row table.
public struct ListDetail: Sendable, Equatable, Identifiable {
    public let summary: ListSummary
    /// The schema DSL string from the API (e.g. `"Title:text, Year:number"`).
    /// `nil` when the API omits it — older or unstructured lists may have no
    /// schema set yet.
    public let schemaDescription: String?
    /// Optional parent list id for nested lists (PLAN.md §1 "Nested lists").
    /// The hierarchy UI is a later-milestone deliverable; the field is
    /// surfaced here so detail views render the breadcrumb when present.
    public let parentID: String?

    public var id: String { summary.id }
    public var title: String { summary.title }
    public var description: String? { summary.description }
    public var visibility: Visibility { summary.visibility }
    public var createdAt: Date? { summary.createdAt }
    public var updatedAt: Date? { summary.updatedAt }

    public init(
        summary: ListSummary,
        schemaDescription: String? = nil,
        parentID: String? = nil
    ) {
        self.summary = summary
        self.schemaDescription = schemaDescription
        self.parentID = parentID
    }
}
