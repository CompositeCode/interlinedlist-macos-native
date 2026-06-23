import Foundation

/// A directed connection between two lists — the public projection of
/// `ListConnectionDTO`, the data the M3 ERD / graph canvas renders
/// (PLAN.md §1 "List connections", §6 M3).
///
/// Connections are addressable individually by `id` for delete. `label` is
/// the optional caption the editor surfaces above each edge in the graph.
public struct ListConnection: Sendable, Equatable, Hashable, Identifiable {

    public let id: String

    /// Source list id (edge tail).
    public let fromListId: String

    /// Destination list id (edge head).
    public let toListId: String

    /// Optional human-readable label for the edge.
    public let label: String?

    public let createdAt: Date?

    public init(
        id: String,
        fromListId: String,
        toListId: String,
        label: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.fromListId = fromListId
        self.toListId = toListId
        self.label = label
        self.createdAt = createdAt
    }
}
