import Foundation

/// Seed domain model so the `Models/` folder is populated and tests have
/// something concrete to exercise. Replaced in Wave 1 with real domain
/// models (Message, ListDefinition, Document, Profile, Organization, etc.)
/// derived from — but never identical to — the kit DTOs (PLAN.md §3
/// "DTOs never cross into the UI").
public struct PlaceholderModel: Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}
